// Mock data generator for Airtable
// Run with: npx ts-node generate-mock-data.ts

import dotenv from 'dotenv';

dotenv.config();

import Airtable from 'airtable';
import { TaskStatus } from './src/types';

const base = new Airtable({
    apiKey: process.env.AIRTABLE_PERSONAL_ACCESS_TOKEN
}).base(process.env.AIRTABLE_BASE_ID!);

const TASKS_TABLE = 'Tasks';
const STAFF_TABLE = 'Staff';

// Mock product data based on the provided structure
const mockProducts = [
    {
        id: "gid://shopify/LineItem/13225628860500",
        sku: "YAMA-TS-001",
        name: "山ノ内オリジナルTシャツ　Long Sleeve Black - サル Monkey / S / ユニセックス",
        image_url: "https://example.com/tshirt-monkey-s.jpg",
        variant_title: "サル Monkey / S / ユニセックス",
        quantity_required: 3
    },
    {
        id: "gid://shopify/LineItem/13225628860501",
        sku: "YAMA-TS-002",
        name: "山ノ内オリジナルTシャツ　Short Sleeve White - トラ Tiger / M / ユニセックス",
        image_url: "https://example.com/tshirt-tiger-m.jpg",
        variant_title: "トラ Tiger / M / ユニセックス",
        quantity_required: 2
    },
    {
        id: "gid://shopify/LineItem/13225628860502",
        sku: "YAMA-CAP-001",
        name: "山ノ内オリジナルキャップ - ブラック / フリーサイズ",
        image_url: "https://example.com/cap-black.jpg",
        variant_title: "ブラック / フリーサイズ",
        quantity_required: 1
    },
    {
        id: "gid://shopify/LineItem/13225628860503",
        sku: "YAMA-BAG-001",
        name: "山ノ内エコバッグ - ナチュラル / レギュラー",
        image_url: "https://example.com/ecobag-natural.jpg",
        variant_title: "ナチュラル / レギュラー",
        quantity_required: 5
    },
    {
        id: "gid://shopify/LineItem/13225628860504",
        sku: null,
        name: "山ノ内オリジナルマグカップ - ホワイト / 350ml",
        image_url: null,
        variant_title: "ホワイト / 350ml",
        quantity_required: 2
    }
];

const mockStaffNames = [
    "田中 太郎", "佐藤 花子", "山田 次郎", "鈴木 美咲", "高橋 健太",
    "Alice Johnson", "Bob Smith", "Charlie Brown", "Diana Lee", "Emma Wilson"
];

const mockOrderNames = [
    "ORD-2024-001", "ORD-2024-002", "ORD-2024-003", "ORD-2024-004", "ORD-2024-005",
    "ORD-2024-006", "ORD-2024-007", "ORD-2024-008", "ORD-2024-009", "ORD-2024-010"
];

const mockShippingNames = [
    "山田太郎", "田中花子", "佐藤次郎", "鈴木美咲", "高橋健太",
    "John Doe", "Jane Smith", "Michael Johnson", "Sarah Wilson", "David Brown"
];

function generateRandomChecklist(): string {
    const numItems = Math.floor(Math.random() * 3) + 1; // 1-3 items
    const checklist = [];

    for (let i = 0; i < numItems; i++) {
        const product = mockProducts[Math.floor(Math.random() * mockProducts.length)];
        checklist.push({
            ...product,
            quantity_required: Math.floor(Math.random() * 5) + 1 // 1-5 quantity
        });
    }

    return JSON.stringify(checklist);
}

function getRandomDate(daysAgo: number = 30): string {
    const date = new Date();
    date.setDate(date.getDate() - Math.floor(Math.random() * daysAgo));
    return date.toISOString();
}

async function generateMockData() {
    console.log('🚀 Starting mock data generation...');

    try {
        // 1. Generate Staff Members
        console.log('\n📋 Creating staff members...');
        const staffIds: string[] = [];

        for (const name of mockStaffNames) {
            try {
                const record = await base(STAFF_TABLE).create({
                    name: name
                });
                staffIds.push((record as any).id);
                console.log(`✅ Created staff: ${name} (${(record as any).id})`);
            } catch (error) {
                console.log(`⚠️  Staff ${name} might already exist, skipping...`);
            }
        }

        // Get all existing staff if creation failed
        if (staffIds.length === 0) {
            console.log('📖 Fetching existing staff...');
            const existingStaff = await base(STAFF_TABLE).select().all();
            staffIds.push(...existingStaff.map(record => (record as any).id));
        }

        // 2. Generate Tasks
        console.log('\n📦 Creating fulfillment tasks...');

        const statuses = [
            TaskStatus.PENDING,
            TaskStatus.PICKING,
            TaskStatus.PACKED,
            TaskStatus.INSPECTING,
            TaskStatus.COMPLETED,
            TaskStatus.PAUSED
        ];

        for (let i = 0; i < mockOrderNames.length; i++) {
            const status = statuses[Math.floor(Math.random() * statuses.length)];
            const createdAt = getRandomDate();
            const taskData: any = {
                order_name: mockOrderNames[i],
                status: status,
                shipping_name: mockShippingNames[i],
                created_at: createdAt,
                updated_at: createdAt,
                checklist_json: generateRandomChecklist()
            };

            // Add status-specific timestamps
            if (status !== TaskStatus.PENDING) {
                // Skip operator assignment for now due to schema issues
                // taskData.current_operator = [randomStaffId];

                if (status === TaskStatus.PICKING || status === TaskStatus.PACKED ||
                    status === TaskStatus.INSPECTING || status === TaskStatus.COMPLETED) {
                    taskData.started_at = getRandomDate(7);
                }

                if (status === TaskStatus.PACKED || status === TaskStatus.INSPECTING ||
                    status === TaskStatus.COMPLETED) {
                    taskData.picked_at = getRandomDate(5);
                }

                if (status === TaskStatus.INSPECTING || status === TaskStatus.COMPLETED) {
                    taskData.start_inspection_at = getRandomDate(3);
                }

                if (status === TaskStatus.COMPLETED) {
                    taskData.completed_at = getRandomDate(1);
                }
            }

            try {
                const record = await base(TASKS_TABLE).create(taskData);
                console.log(`✅ Created task: ${taskData.order_name} (${status}) - ${(record as any).id}`);
            } catch (error) {
                console.error(`❌ Failed to create task ${taskData.order_name}:`, error);
            }
        }

        console.log('\n🎉 Mock data generation completed!');
        console.log('\n📊 Summary:');
        console.log(`- Staff members: ${mockStaffNames.length}`);
        console.log(`- Tasks: ${mockOrderNames.length}`);
        console.log('- Products in checklist: Various Japanese merchandise items');

    } catch (error) {
        console.error('❌ Mock data generation failed:', error);
    }
}

async function clearExistingData() {
    console.log('🧹 Clearing existing mock data...');

    try {
        // Clear tasks
        const tasks = await base(TASKS_TABLE).select().all();
        for (const task of tasks) {
            await base(TASKS_TABLE).destroy((task as any).id);
            console.log(`🗑️  Deleted task: ${(task as any).id}`);
        }

        // Clear staff
        const staff = await base(STAFF_TABLE).select().all();
        for (const member of staff) {
            await base(STAFF_TABLE).destroy((member as any).id);
            console.log(`🗑️  Deleted staff: ${(member as any).id}`);
        }

        console.log('✅ Existing data cleared!');
    } catch (error) {
        console.error('❌ Failed to clear data:', error);
    }
}

// Main execution
async function main() {
    const args = process.argv.slice(2);

    if (args.includes('--clear')) {
        await clearExistingData();
        return;
    }

    if (args.includes('--fresh')) {
        await clearExistingData();
        await generateMockData();
        return;
    }

    await generateMockData();
}

main();