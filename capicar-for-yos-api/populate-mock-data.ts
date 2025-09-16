import Airtable from 'airtable';
import dotenv from 'dotenv';

// Load environment variables
dotenv.config();

// Initialize Airtable
const base = new Airtable({ apiKey: process.env.AIRTABLE_PERSONAL_ACCESS_TOKEN })
  .base(process.env.AIRTABLE_BASE_ID!);

// Mock Staff Data
const mockStaff = [
  {
    staff_id: 'S001',
    name: 'Alice Johnson',
    is_active: true,
    currently_selected: false
  },
  {
    staff_id: 'S002', 
    name: 'Bob Wilson',
    is_active: true,
    currently_selected: false
  },
  {
    staff_id: 'S003',
    name: 'Carol Davis',
    is_active: true,
    currently_selected: false
  },
  {
    staff_id: 'S004',
    name: 'David Miller',
    is_active: true,
    currently_selected: false
  },
  {
    staff_id: 'S005',
    name: 'Emma Wilson',
    is_active: false,
    currently_selected: false
  }
];

// Mock Task Data
const mockTasks = [
  {
    task_id: 'T001',
    shopify_order_id: 'ORD-2024-001',
    order_name: '#1001',
    status: 'Pending',
    is_incident: false,
    current_operator: null,
    exception_assigned_to: null,
    in_exception_pool: false,
    checklist_json: JSON.stringify([
      { id: '1', description: 'Pick item: Blue T-Shirt Size M', completed: false, location: 'A1-B2' },
      { id: '2', description: 'Pick item: Jeans Size 32', completed: false, location: 'B3-C4' }
    ]),
    checklist_incomplete: 2,
    tracking_number: null,
    return_tracking_number: null,
    shipping_name: 'John Doe',
    shipping_address1: '123 Main St',
    shipping_address2: 'Apt 4B',
    shipping_city: 'Toronto',
    shipping_province: 'ON',
    shipping_zip: 'M5H 2N2',
    shipping_phone: '+1-416-555-0123',
    shipping_weight: null,
    shipping_dimensions: null,
    exception_reason: null,
    correction_notes: null,
    resolution_action: null,
    resolution_notes: null,
    started_at: null,
    picked_at: null,
    packed_at: null,
    start_inspection_at: null,
    completed_at: null,
    cancelled_at: null,
    cancellation_conflict: null,
    exception_logged_at: null,
    return_to_pending_at: null,
    created_at: new Date().toISOString(),
    updated_at: new Date().toISOString()
  },
  {
    task_id: 'T002',
    shopify_order_id: 'ORD-2024-002',
    order_name: '#1002',
    status: 'Picking',
    is_incident: false,
    current_operator: 'Alice Johnson',
    exception_assigned_to: null,
    in_exception_pool: false,
    checklist_json: JSON.stringify([
      { id: '1', description: 'Pick item: Red Hoodie Size L', completed: true, location: 'C1-D2' },
      { id: '2', description: 'Pick item: Black Sneakers Size 9', completed: false, location: 'D3-E4' }
    ]),
    checklist_incomplete: 1,
    tracking_number: null,
    return_tracking_number: null,
    shipping_name: 'Jane Smith',
    shipping_address1: '456 Oak Ave',
    shipping_address2: null,
    shipping_city: 'Vancouver',
    shipping_province: 'BC',
    shipping_zip: 'V6B 2W8',
    shipping_phone: '+1-604-555-0456',
    shipping_weight: null,
    shipping_dimensions: null,
    exception_reason: null,
    correction_notes: null,
    resolution_action: null,
    resolution_notes: null,
    started_at: new Date(Date.now() - 3600000).toISOString(), // 1 hour ago
    picked_at: null,
    packed_at: null,
    start_inspection_at: null,
    completed_at: null,
    cancelled_at: null,
    cancellation_conflict: null,
    exception_logged_at: null,
    return_to_pending_at: null,
    created_at: new Date(Date.now() - 7200000).toISOString(), // 2 hours ago
    updated_at: new Date().toISOString()
  },
  {
    task_id: 'T003',
    shopify_order_id: 'ORD-2024-003',
    order_name: '#1003',
    status: 'Packed',
    is_incident: false,
    current_operator: 'Bob Wilson',
    exception_assigned_to: null,
    in_exception_pool: false,
    checklist_json: JSON.stringify([
      { id: '1', description: 'Pick item: Green Cap', completed: true, location: 'A5-B6' },
      { id: '2', description: 'Pick item: Blue Socks (2 pairs)', completed: true, location: 'B7-C8' }
    ]),
    checklist_incomplete: 0,
    tracking_number: null,
    return_tracking_number: null,
    shipping_name: 'Mike Brown',
    shipping_address1: '789 Pine St',
    shipping_address2: 'Unit 15',
    shipping_city: 'Calgary',
    shipping_province: 'AB',
    shipping_zip: 'T2P 1J9',
    shipping_phone: '+1-403-555-0789',
    shipping_weight: '0.5kg',
    shipping_dimensions: '20x15x5cm',
    exception_reason: null,
    correction_notes: null,
    resolution_action: null,
    resolution_notes: null,
    started_at: new Date(Date.now() - 10800000).toISOString(), // 3 hours ago
    picked_at: new Date(Date.now() - 7200000).toISOString(), // 2 hours ago
    packed_at: new Date(Date.now() - 3600000).toISOString(), // 1 hour ago
    start_inspection_at: null,
    completed_at: null,
    cancelled_at: null,
    cancellation_conflict: null,
    exception_logged_at: null,
    return_to_pending_at: null,
    created_at: new Date(Date.now() - 14400000).toISOString(), // 4 hours ago
    updated_at: new Date().toISOString()
  },
  {
    task_id: 'T004',
    shopify_order_id: 'ORD-2024-004',
    order_name: '#1004',
    status: 'Inspecting',
    is_incident: false,
    current_operator: 'Carol Davis',
    exception_assigned_to: null,
    in_exception_pool: false,
    checklist_json: JSON.stringify([
      { id: '1', description: 'Pick item: White Dress Size S', completed: true, location: 'E1-F2' },
      { id: '2', description: 'Pick item: Gold Necklace', completed: true, location: 'F3-G4' }
    ]),
    checklist_incomplete: 0,
    tracking_number: null,
    return_tracking_number: null,
    shipping_name: 'Sarah Connor',
    shipping_address1: '321 Elm St',
    shipping_address2: null,
    shipping_city: 'Montreal',
    shipping_province: 'QC',
    shipping_zip: 'H3A 0B5',
    shipping_phone: '+1-514-555-0321',
    shipping_weight: '0.3kg',
    shipping_dimensions: '25x20x3cm',
    exception_reason: null,
    correction_notes: null,
    resolution_action: null,
    resolution_notes: null,
    started_at: new Date(Date.now() - 18000000).toISOString(), // 5 hours ago
    picked_at: new Date(Date.now() - 14400000).toISOString(), // 4 hours ago
    packed_at: new Date(Date.now() - 10800000).toISOString(), // 3 hours ago
    start_inspection_at: new Date(Date.now() - 1800000).toISOString(), // 30 minutes ago
    completed_at: null,
    cancelled_at: null,
    cancellation_conflict: null,
    exception_logged_at: null,
    return_to_pending_at: null,
    created_at: new Date(Date.now() - 21600000).toISOString(), // 6 hours ago
    updated_at: new Date().toISOString()
  },
  {
    task_id: 'T005',
    shopify_order_id: 'ORD-2024-005',
    order_name: '#1005',
    status: 'Correction_Needed',
    is_incident: true,
    current_operator: null,
    exception_assigned_to: 'David Miller',
    in_exception_pool: true,
    checklist_json: JSON.stringify([
      { id: '1', description: 'Pick item: Purple Scarf', completed: true, location: 'G1-H2' },
      { id: '2', description: 'Pick item: Winter Gloves Size M', completed: true, location: 'H3-I4' }
    ]),
    checklist_incomplete: 0,
    tracking_number: null,
    return_tracking_number: null,
    shipping_name: 'Tom Anderson',
    shipping_address1: '654 Maple Ave',
    shipping_address2: 'Suite 8',
    shipping_city: 'Halifax',
    shipping_province: 'NS',
    shipping_zip: 'B3H 4R2',
    shipping_phone: '+1-902-555-0654',
    shipping_weight: '0.4kg',
    shipping_dimensions: '22x18x4cm',
    exception_reason: 'Item damaged during inspection',
    correction_notes: 'Purple scarf has small tear, needs replacement',
    resolution_action: null,
    resolution_notes: null,
    started_at: new Date(Date.now() - 25200000).toISOString(), // 7 hours ago
    picked_at: new Date(Date.now() - 21600000).toISOString(), // 6 hours ago
    packed_at: new Date(Date.now() - 18000000).toISOString(), // 5 hours ago
    start_inspection_at: new Date(Date.now() - 14400000).toISOString(), // 4 hours ago
    completed_at: null,
    cancelled_at: null,
    cancellation_conflict: null,
    exception_logged_at: new Date(Date.now() - 10800000).toISOString(), // 3 hours ago
    return_to_pending_at: null,
    created_at: new Date(Date.now() - 28800000).toISOString(), // 8 hours ago
    updated_at: new Date().toISOString()
  },
  {
    task_id: 'T006',
    shopify_order_id: 'ORD-2024-006',
    order_name: '#1006',
    status: 'Completed',
    is_incident: false,
    current_operator: null,
    exception_assigned_to: null,
    in_exception_pool: false,
    checklist_json: JSON.stringify([
      { id: '1', description: 'Pick item: Black Jacket Size L', completed: true, location: 'I1-J2' },
      { id: '2', description: 'Pick item: Brown Belt Size 34', completed: true, location: 'J3-K4' }
    ]),
    checklist_incomplete: 0,
    tracking_number: 'TRK123456789',
    return_tracking_number: null,
    shipping_name: 'Lisa Johnson',
    shipping_address1: '987 Cedar Rd',
    shipping_address2: null,
    shipping_city: 'Winnipeg',
    shipping_province: 'MB',
    shipping_zip: 'R3T 2N6',
    shipping_phone: '+1-204-555-0987',
    shipping_weight: '1.2kg',
    shipping_dimensions: '30x25x8cm',
    exception_reason: null,
    correction_notes: null,
    resolution_action: null,
    resolution_notes: null,
    started_at: new Date(Date.now() - 43200000).toISOString(), // 12 hours ago
    picked_at: new Date(Date.now() - 39600000).toISOString(), // 11 hours ago
    packed_at: new Date(Date.now() - 36000000).toISOString(), // 10 hours ago
    start_inspection_at: new Date(Date.now() - 32400000).toISOString(), // 9 hours ago
    completed_at: new Date(Date.now() - 28800000).toISOString(), // 8 hours ago
    cancelled_at: null,
    cancellation_conflict: null,
    exception_logged_at: null,
    return_to_pending_at: null,
    created_at: new Date(Date.now() - 46800000).toISOString(), // 13 hours ago
    updated_at: new Date().toISOString()
  }
];

async function populateStaff() {
  console.log('🧑‍💼 Creating staff members...');
  
  try {
    const createdRecords = await base('Staff').create(mockStaff);
    console.log(`✅ Created ${createdRecords.length} staff members`);
    return createdRecords;
  } catch (error) {
    console.error('❌ Error creating staff:', error);
    throw error;
  }
}

async function populateTasks() {
  console.log('📦 Creating tasks...');
  
  try {
    const createdRecords = await base('Task').create(mockTasks);
    console.log(`✅ Created ${createdRecords.length} tasks`);
    return createdRecords;
  } catch (error) {
    console.error('❌ Error creating tasks:', error);
    throw error;
  }
}

async function main() {
  console.log('🚀 Starting to populate Airtable with mock data...\n');

  try {
    // Create staff first
    await populateStaff();
    console.log();
    
    // Then create tasks
    await populateTasks();
    console.log();
    
    console.log('🎉 Successfully populated Airtable with mock data!');
    console.log('\nMock data includes:');
    console.log('- 5 staff members (4 active, 1 inactive)');
    console.log('- 6 tasks across different statuses:');
    console.log('  • Pending: T001');
    console.log('  • Picking: T002');
    console.log('  • Packed: T003');
    console.log('  • Inspecting: T004');
    console.log('  • Correction_Needed: T005');
    console.log('  • Completed: T006');
    
  } catch (error) {
    console.error('💥 Failed to populate data:', error);
    process.exit(1);
  }
}

// Run the script
main();