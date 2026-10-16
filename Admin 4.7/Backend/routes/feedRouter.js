import express from 'express';
import Redis from 'ioredis';
import { createClient } from '@supabase/supabase-js';
import { refreshGeneralNewsFeed } from '../services/generalFeedService.js';
import { syncStudentData } from '../services/studentSyncService.js';
import bcourses from '../services/courses_table.js';
import { decrypt_with_blob } from './profileRoutes.js'
import { authenticate } from '../services/auth.js';

const router = express.Router();
const redis = new Redis(process.env.REDIS_URL || 'redis://campus_redis:6379');
const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_KEY);

// GET /api/feed/general
router.get('/general', async (req, res) => {
  try {
    const cachedData = await redis.get('feed:general:today');
    if (cachedData) {
      return res.json({ source: 'cache', items: JSON.parse(cachedData) });
    }

    const { data, error } = await supabase.from('feed_items').select('*').limit(20);
    if (error) throw error;
    
    return res.json({ source: 'database', items: data || [] });
  } catch (error) {
    return res.status(500).json({ error: 'Failed to retrieve general news.' });
  }
});

// POST /api/feed/general/refresh
router.post('/general/refresh', async (req, res) => {
  try {
    const items = await refreshGeneralNewsFeed();

    return res.status(200).json({
      message: 'Firecrawl scraper executed successfully & Redis refreshed! GOAL',
      count: items.length
    });
  } catch (error) {
    return res.status(500).json({ error: error.message });
  }
});

// POST /api/feed/personalized
router.post('/personalized', async (req, res) => {
    try {
      let { collegeId, password, allStudentCourses,uuid} = req.body;
      const forceRefresh = req.query.refresh === 'true'; // Check for ?refresh=true
console.log(`${collegeId} + ${password} + ${allStudentCourses} + ${uuid}`);
      if (!collegeId || !password || !allStudentCourses || !uuid) {
        return res.status(400).json({ error: 'collegeId, password, uuid and allStudentCourses are required' });
      }
      
      const auth = await authenticate(req, res);
      console.log(auth);
      if (!auth) return; // response already sent
      const { db } = auth;
      
      // password can be an encrypted blob so let's check
          

          if(password.length >29){ //probably blob
            console.log(password);
            password = decrypt_with_blob(password);
            // After decryption
          }
          console.log("After decryption");
          console.log(password);

      console.log("////////// moment of truth");
      console.log(allStudentCourses);

    // Resolve indices -> {course_name, course_url} objects
    const studentCourses = allStudentCourses.map(idx => bcourses[idx]);
    const studentCourseNames = studentCourses.map(c => c.course_name);

    const cleanNames = studentCourseNames.map(n => n.trim().normalize('NFC'));

     console.log(cleanNames);

    // 1. Fetch all available courses in one query, matched by name
    const { data: availableCourses, error } = await db
      .from('course_activities')
      .select('*')
      .in('course_name', cleanNames);
      console.log(cleanNames);
    if (error) throw error;

    console.log('Searching for:', studentCourseNames);
console.log('Query result:', availableCourses, error);
console.log(studentCourseNames[0].split('').map(c => c.charCodeAt(0)));

    // 2. Which names came back from Supabase?
    const availableNames = new Set(availableCourses.map(c => c.course_name));

    // 3. Get back the ORIGINAL indices (not names) for the courses that are missing —
    //    syncStudentData needs bcourses indices, not names
    const missingIndices = allStudentCourses.filter(
      (idx, i) => !availableNames.has(studentCourseNames[i])
    );
    console.log("one last check before going to syncStudentData");
    console.log(missingIndices);

    // 4. Scrape only the missing ones
    let scrapedData = [];
    if (missingIndices.length > 0) {
      console.log("let's check password one last time"); 
      console.log(password);
      console.log(collegeId);
      scrapedData = await syncStudentData(req,res,collegeId, password, forceRefresh, missingIndices);
    }
    console.log("scrapped Data in feedRouter.js");
    console.log(scrapedData.length);

    // 5. Merge: Error: scrapedData is an object {}
    // using the spread operator (...) requires both variables to be arrays
    // scrappedData isn't an array , it's an object with 2 arrays inside
    let mergedData;
    
    if (scrapedData.length != 0) {
       mergedData = [...availableCourses,
        ...scrapedData.all_activities];
    }else{
       mergedData = [...availableCourses];
    }
    

    return res.json({
      source: forceRefresh ? 'live' : 'live_or_cache',
      data: mergedData,
    });
  
    } catch (error) {
      console.error('Personalized feed error:', error.message);
      return res.status(500).json({ error: error.message || 'Failed to sync student data' });
    }
  });

export default router;

/*
      //////////////// *************** ///////////////////////
      let studentCourses = [];
      let availableCourses = [];
      for(let i = 0; i< allStudentCourses.length; i++){
        studentCourses.push(bcourses[allStudentCourses[i]]);
       }
       //////////////// *************** ///////////////////////
       for(let i = 0; i< allStudentCourses.length; i++){
        availableCourses.push(await supabase.from('course_activities').select('course_name').eq(studentCourses[i]));
       }

          const data = await syncStudentData(collegeId, password, forceRefresh,allStudentCourses);
      return res.json({ source: forceRefresh ? 'live' : 'live_or_cache', data });
*/