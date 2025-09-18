// Create this as a temporary file in your project root to test Airtable connection
// Run with: npx ts-node test-airtable.ts

import dotenv from 'dotenv';

dotenv.config();

import { airtableService } from './src/services/airtableService';

async function testConnection() {
    console.log('Testing Airtable connection...');
    console.log('Environment variables:');
    console.log('AIRTABLE_PERSONAL_ACCESS_TOKEN:', process.env.AIRTABLE_PERSONAL_ACCESS_TOKEN ? '***loaded***' : 'NOT FOUND');
    console.log('AIRTABLE_BASE_ID:', process.env.AIRTABLE_BASE_ID || 'NOT FOUND');

    try {
        // Test fetching tasks
        console.log('Fetching tasks...');
        const tasks = await airtableService.getAllTasks();
        console.log(`Successfully fetched ${tasks.length} tasks`);

        if (tasks.length > 0) {
            console.log('Sample task:', JSON.stringify(tasks[0], null, 2));
        }

        // Test fetching staff
        console.log('\nFetching staff...');
        const staff = await airtableService.getAllStaff();
        console.log(`Successfully fetched ${staff.length} staff members`);

        if (staff.length > 0) {
            console.log('Sample staff:', JSON.stringify(staff[0], null, 2));
        }

        console.log('\n✅ Airtable connection successful!');

    } catch (error) {
        console.error('❌ Airtable connection failed:', error);
    }
}

testConnection();