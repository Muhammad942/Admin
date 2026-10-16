import axios from 'axios';
import { createClient } from '@supabase/supabase-js';
import Redis from 'ioredis';
import * as cheerio from 'cheerio';
import crypto from 'crypto';
import bcourses from './courses_table.js';
import { authenticate } from './auth.js';

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_KEY);
const redis = new Redis(process.env.REDIS_URL || 'redis://campus_redis:6379');

// Moodle prints dates in the LMS user's timezone, with no timezone info.
// Set this to the college's UTC offset in hours (e.g. 2 or 3) so due dates are stored correctly.
// Defaults to 0 (treat the printed time as UTC).
const LMS_UTC_OFFSET_HOURS = Number(process.env.LMS_UTC_OFFSET_HOURS ?? 0);

const MONTHS = {
  january: 0, february: 1, march: 2, april: 3, may: 4, june: 5,
  july: 6, august: 7, september: 8, october: 9, november: 10, december: 11,
};

/**
 * Parses Moodle dates like "Thursday, 31 December 2026, 12:00 AM" into an ISO string.
 * Done manually so it doesn't depend on the server's locale / Date.parse quirks.
 */
function parseMoodleDate(text) {
  if (!text) return null;
  const m = text
    .replace(/\s+/g, ' ')
    .match(/(\d{1,2})\s+([A-Za-z]+)\s+(\d{4}),?\s+(\d{1,2}):(\d{2})\s*(AM|PM)?/i);
  if (!m) return null;

  const day = parseInt(m[1], 10);
  const month = MONTHS[m[2].toLowerCase()];
  const year = parseInt(m[3], 10);
  let hour = parseInt(m[4], 10);
  const minute = parseInt(m[5], 10);
  const meridiem = m[6]?.toUpperCase();

  if (month === undefined) return null;
  if (meridiem === 'PM' && hour < 12) hour += 12;
  if (meridiem === 'AM' && hour === 12) hour = 0;

  const date = new Date(Date.UTC(year, month, day, hour - LMS_UTC_OFFSET_HOURS, minute));
  return isNaN(date.getTime()) ? null : date.toISOString();
}

/** Finds the "Due:" / "Closes:" line inside an activity's dates block. */
function extractDueDate($, $el) {
  let dueDate = null;

  $el.find('[data-region="activity-dates"] div, .activity-dates div').each((_, div) => {
    // Collapse whitespace FIRST: the raw text starts with newlines/spaces before <strong>,
    // which is why an anchored /^Due:/ regex on the untrimmed text never matched.
    const text = $(div).text().replace(/\s+/g, ' ').trim();
    const match = text.match(/^(?:Due|Closes|Cut-off date):\s*(.+)$/i);
    if (match) {
      dueDate = parseMoodleDate(match[1]);
      return false; // stop at the first match
    }
  });

  return dueDate;
}

/** Plain insert of a course's activities into the course_activities table. */
async function saveActivitiesToSupabase(req,res,activities) {
  const rows = activities.map(a => ({
    id: a.id,                                  // uuid (generated in the scraper)
    course_name: a.course_name,
    name: a.name,
    description: a.description,
    pdf_url: a.pdf_url,
    activity_url: a.activity_url,
    due_date: a.due_date,                      // ISO string -> timestamptz
    is_deadline: a.is_deadline,
    moodle_course_id: a.moodle_course_id,      // int4
    // created_at is filled by its default (now())
  }));

  if (rows.length === 0) {
    console.log('⚠️ No activities to save for this course.');
    return;
  }

  const auth = await authenticate(req, res);
  console.log(auth);
  if (!auth) return; // response already sent
  const { db } = auth;

  const { data, error } = await db
    .from('course_activities')
    .insert(rows)
    .select('id');

  if (error) {
    console.error('❌ Supabase insert failed:', error.message, error.details, error.hint);
  } else {
    console.log(`💾 Inserted ${data.length} activities for "${rows[0].course_name}"`);
  }
}

export async function fetchStudentCourses(collegeId, password) {
    const apiKey = process.env.FIRECRAWL_API_KEY;
  
    console.log(`🔥 Starting authenticated crawl for student: ${collegeId}`);
  
    try {
      const response = await axios.post(
        'https://api.firecrawl.dev/v2/scrape',
        {
          url: 'https://lmscis.com/login/index.php',
          formats: [
            {
              type: 'json',
              prompt: 'Extract all actual enrolled subject courses from the student dashboard. Completely IGNORE the main dashboard or "مقرراتي الدراسية" (course id 1). Only extract links that point to specific individual subject courses (where course id is greater than 1, e.g., view.php?id=431).',
            schema: {
                type: 'object',
                properties: {
                  courses: {
                    type: 'array',
                    items: {
                      type: 'object',
                      properties: {
                        course_name: { type: 'string' },
                        course_url: { 
                          type: 'string', 
                          description: 'The direct link to the specific subject course page (must have id > 1)' 
                        }
                      },
                      required: ['course_name', 'course_url']
                    }
                  }
                },
                required: ['courses']
              }
            }
          ],
          actions: [
            // 1. Focus and enter Username
            { type: 'click', selector: '#username' },
            { type: 'write', text: collegeId },
  
            // 2. Focus and enter Password
            { type: 'click', selector: '#password' },
            { type: 'write', text: password },
  
            // 3. Submit Form
            { type: 'click', selector: '#loginbtn' },
            
            // 4. Wait for dashboard redirect to load course cards/links
            { type: 'wait', milliseconds: 6000 }
          ]
        },
        {
          headers: {
            'Authorization': `Bearer ${apiKey}`,
            'Content-Type': 'application/json'
          }
        }
      );
  
      const rawCourses = response.data?.data?.json?.courses || [];
    
      // Safety Filter: Exclude id=1 or "مقرراتي الدراسية" just in case Firecrawl grabs it anyway
      const extractedCourses = rawCourses.filter(course => {
        const isDashboard = course.course_url.includes('id=1') || course.course_name.includes('مقرراتي الدراسية');
        return !isDashboard;
      });
  
      console.log(`✅ Extracted ${extractedCourses.length} valid courses:`, extractedCourses);
      return extractedCourses;
  
    } catch (error) {
      console.error('🔥 Full Firecrawl Error Response:', JSON.stringify(error.response?.data || error.message, null, 2));
      throw new Error(error.response?.data?.error || 'Failed to authenticate and fetch courses.');
    }
}

export async function scrapeCourseDetails(courseUrl, collegeId, password) {
    const apiKey = process.env.FIRECRAWL_API_KEY;
  
    console.log(`🔥 Scraping course activities from: ${courseUrl}`);
  
    try {
      const response = await axios.post(
        'https://api.firecrawl.dev/v2/scrape',
        {
          url: courseUrl, // Moodle redirects to login/index.php if unauthenticated
          formats: ['html'],
          onlyMainContent: false,
          actions: [
            // 1. Enter Credentials on Moodle Login Form
            { type: 'click', selector: '#username' },
            { type: 'write', text: collegeId },
            { type: 'click', selector: '#password' },
            { type: 'write', text: password },
            { type: 'click', selector: '#loginbtn' },
  
            // 2. Wait for login and redirect back to the course page
            { type: 'wait', milliseconds: 6000 }
          ]
        },
        {
          headers: {
            'Authorization': `Bearer ${apiKey}`,
            'Content-Type': 'application/json'
          }
        }
      );
  
      const rawHtml = response.data?.data?.html || '';
      const $ = cheerio.load(rawHtml);
      const activities = [];

      // Moodle nests div.activity-item inside li.activity. Matching both (as before) visited
      // every activity twice, so use li.activity and only fall back if the theme has none.
      let activityElements = $('li.activity');
      if (activityElements.length === 0) activityElements = $('.activity-item');

      activityElements.each((_, element) => {
        const $el = $(element);

        // Name: take ONLY the first .instancename and drop the hidden type label
        // (<span class="accesshide"> Assignment</span>). Using ".activityname, .instancename"
        // together is what produced the doubled, whitespace-filled names.
        const $title = $el.find('.instancename').first().clone();
        $title.find('.accesshide').remove();
        const name = ($el.attr('data-activityname') || $title.text())
          .replace(/\s+/g, ' ')
          .replace(/^Select activity\s*/i, '')
          .trim();

        const activityUrl = $el.find('.activityname a, a.aalink').first().attr('href')
          || $el.find('a').first().attr('href')
          || '';

        const description = $el
          .find('.contentafterlink, .activity-description, .no-overflow')
          .first()
          .text()
          .replace(/\s+/g, ' ')
          .trim();

        const dueDate = extractDueDate($, $el);

        if (name) {
          activities.push({
            id: crypto.randomUUID(),
            name,
            description: description || null,
            pdf_url: activityUrl.includes('.pdf') || activityUrl.includes('/resource/') ? activityUrl : null,
            activity_url: activityUrl,
            due_date: dueDate,
            is_deadline: dueDate !== null && new Date(dueDate) > new Date()
          });
        }
      });
  
      console.log(`✅ Extracted ${activities.length} activities from course page.`);
      return activities;
  
    } catch (error) {
      console.error(`❌ Error scraping ${courseUrl}:`, error.response?.data || error.message);
      return [];
    }
  }

export async function syncStudentData(req,res,studentId, password, forceRefresh = false, allStudentCourses = []) {
    const userCacheKey = `student:${studentId}:courses`;
    let courses = [];

    // Check Redis cache unless forced refresh
    if (!forceRefresh) {
      const cachedData = await redis.get(userCacheKey);
      if (cachedData) {
        console.log('⚡ Returning cached student course deadlines!');
        return JSON.parse(cachedData);
      }
    } else {
      console.log('🔄 Force refreshing cache for student...');
    }
  
    // Resolve the student's selected courses from the local courses table
    for (const key of allStudentCourses) {
      if (bcourses[key]) courses.push(bcourses[key]);
      else console.warn(`⚠️ No course found in courses_table for key: ${key}`);
    }
  
    let allActivities = [];
  
    for (const course of courses) {
      const items = await scrapeCourseDetails(course.course_url, studentId, password);
      console.log(`📚 ${course.course_name}: ${items.length} activities`);

      // Moodle course id from the URL, e.g. ".../course/view.php?id=431" -> 431
      const moodleCourseId = parseInt(new URL(course.course_url).searchParams.get('id'), 10) || null;

      const taggedItems = items.map(item => ({
        ...item,
        course_name: course.course_name,
        moodle_course_id: moodleCourseId
      }));

      // Insert this course's activities into the Supabase table
      await saveActivitiesToSupabase(req,res,taggedItems);

      allActivities.push(...taggedItems);
    }
  
    // Filter deadlines in the upcoming 24 hours
    const now = new Date();
    const next24h = new Date(now.getTime() + 24 * 60 * 60 * 1000);
  
    const dueNext24hrs = allActivities.filter(act => {
      if (!act.due_date) return false;
      const d = new Date(act.due_date);
      return d >= now && d <= next24h;
    });
  
    const resultPayload = {
      all_activities: allActivities,
      due_next_24hrs: dueNext24hrs
    };
  
    // Cache in Redis for 1 hour
    await redis.set(userCacheKey, JSON.stringify(resultPayload), 'EX', 3600);
  
    return resultPayload;
  }