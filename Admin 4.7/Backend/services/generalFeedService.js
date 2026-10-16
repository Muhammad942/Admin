import axios from 'axios';
import { createClient } from '@supabase/supabase-js';
import Redis from 'ioredis';
import * as cheerio from 'cheerio';

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_KEY);
const redis = new Redis(process.env.REDIS_URL || 'redis://campus_redis:6379');

export async function scrapeCollegeNews() {
    const apiKey = process.env.FIRECRAWL_API_KEY;
    const baseUrl = 'https://www.cis.edu.eg';
    const targetUrl = process.env.COLLEGE_NEWS_URL || `${baseUrl}/news`;
  
    const response = await axios.post(
      'https://api.firecrawl.dev/v2/scrape',
      {
        url: targetUrl,
        formats: ['html'], // Get raw HTML instead of Markdown
        onlyMainContent: true
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
    const parsedItems = [];
  
    // Target .irs-courses-content directly
    $('.irs-courses-content').each((index, element) => {
      const titleElement = $(element).find('#newstitle a');
      const title = titleElement.text().trim();
      const relativeUrl = titleElement.attr('href') || '';
      const snippet = $(element).find('#newssubdesc').text().trim();

    // Target the date element relative to the content block using the clock icon
    const dateElementText = $(element).parent().find('i.icofont-clock-time').next('a').text().trim() ||
    $(element).parent().find('.icofont-clock-time').parent().text().trim();

let publishedAt = new Date().toISOString();
if (dateElementText) {
// Clean up whitespace/newlines and parse the date string (e.g., "2026/May/03")
const cleanedDateStr = dateElementText.replace(/\s+/g, ' ').trim();
const parsedDate = new Date(cleanedDateStr);
if (!isNaN(parsedDate.getTime())) {
publishedAt = parsedDate.toISOString();
}
}
  
      if (title) {
        parsedItems.push({
          id: crypto.randomUUID(),
          title: title,
          snippet: snippet,
          url: relativeUrl.startsWith('http') ? relativeUrl : `${baseUrl}${relativeUrl}`,
          published_at: publishedAt
        });
      }
    });
    // 2. Slice array to return only the latest 5 posts
    return parsedItems.slice(0, 5);
  }

export async function refreshGeneralNewsFeed() {
  try {
    const items = await scrapeCollegeNews();

    console.log(items.length);

    // 1. Save / Upsert to Supabase Postgres
    if (items.length > 0) {
      const { error } = await supabase.from('feed_items').insert(items);
      if (error) { console.error('Supabase save error:', error); }
      else{ console.log("Items saved in Supabase successfully !!!"); } 
    }

    // 2. Cache in Redis (expires in 24 hours)
    await redis.set('feed:general:today', JSON.stringify(items), 'EX', 86400);
    console.log('⚡ Redis cache updated for general feed!');

    return items;
  } catch (err) {
    console.error('Failed to refresh feed:', err.response?.data || err.message);
    throw err;
  }
}