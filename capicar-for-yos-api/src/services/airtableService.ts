import Airtable from 'airtable';
import { FulfillmentTask, StaffMember, TaskStatus } from '../types';

// Initialize Airtable
const base = new Airtable({
    apiKey: process.env.AIRTABLE_PERSONAL_ACCESS_TOKEN
}).base(process.env.AIRTABLE_BASE_ID!);

// Table references
const TASKS_TABLE = 'Tasks';
const STAFF_TABLE = 'Staff';
const ORDERS_TABLE = 'Orders';
const AUDIT_LOG_TABLE = 'Audit_Log';

// Cache for dashboard data optimization
interface DashboardCache {
    data: any;
    timestamp: number;
    lastModified: string;
    etag: string;
}

let dashboardCache: DashboardCache | null = null;
const CACHE_TTL = 30000; // 30 seconds cache TTL

// Cache invalidation helper
function invalidateDashboardCache(reason: string) {
    if (dashboardCache) {
        console.log(`🗑️ CACHE INVALIDATED: ${reason}`);
        dashboardCache = null;
    }
}

export class AirtableService {

    // MARK: - Tasks Operations

    async getAllTasks(): Promise<FulfillmentTask[]> {
        try {
            const records = await base(TASKS_TABLE)
                .select({
                    view: 'Grid view', // or your default view name
                    sort: [{ field: 'created_at', direction: 'desc' }]
                })
                .all();

            return await this.mapTaskRecords([...records]); // Convert readonly array to mutable
        } catch (error) {
            console.error('Error fetching tasks:', error);
            throw new Error('Failed to fetch tasks from Airtable');
        }
    }

    async getAllTasksOptimized(): Promise<{ tasks: FulfillmentTask[], lastModified: string, etag: string }> {
        try {
            // Check if we can use cached data
            const now = Date.now();
            if (dashboardCache && (now - dashboardCache.timestamp) < CACHE_TTL) {
                console.log('📦 CACHE HIT: Using cached dashboard data');
                return {
                    tasks: dashboardCache.data,
                    lastModified: dashboardCache.lastModified,
                    etag: dashboardCache.etag
                };
            }

            console.log('🔄 CACHE MISS: Fetching fresh data from Airtable');
            const records = await base(TASKS_TABLE)
                .select({
                    view: 'Grid view',
                    sort: [{ field: 'created_at', direction: 'desc' }]
                })
                .all();

            // Generate cache keys based on data modification times
            const lastModified = new Date().toISOString();
            const recordsHash = records.map(r => `${r.id}-${r.get('updated_at')}`).join('|');
            const etag = `"${Buffer.from(recordsHash).toString('base64').substring(0, 16)}"`;

            // Check if data actually changed (quick hash comparison)
            if (dashboardCache && dashboardCache.etag === etag) {
                console.log('📊 DATA UNCHANGED: Using existing processed data');
                // Update timestamp but keep existing data
                dashboardCache.timestamp = now;
                return {
                    tasks: dashboardCache.data,
                    lastModified: dashboardCache.lastModified,
                    etag: dashboardCache.etag
                };
            }

            // Data changed or no cache - process with batch mapping
            console.log('🔄 DATA CHANGED: Processing with batch mapping');
            const tasks = await this.mapTaskRecords([...records]);

            // Cache the results
            dashboardCache = {
                data: tasks,
                timestamp: now,
                lastModified,
                etag
            };

            return { tasks, lastModified, etag };
        } catch (error) {
            console.error('Error fetching optimized tasks:', error);
            throw new Error('Failed to fetch tasks from Airtable');
        }
    }

    async getTaskById(taskId: string): Promise<FulfillmentTask | null> {
        try {
            const record = await base(TASKS_TABLE).find(taskId);
            return await this.mapTaskRecord(record);
        } catch (error) {
            console.error('Error fetching task:', error);
            return null;
        }
    }

    async updateTaskStatus(taskId: string, status: TaskStatus, operatorId?: string): Promise<FulfillmentTask | null> {
        try {
            const updateFields: any = {
                status: status,
                updated_at: new Date().toISOString()
            };

            // Add status-specific timestamps
            const now = new Date().toISOString();
            switch (status) {
                case TaskStatus.PICKING:
                    updateFields.started_at = now;
                    break;
                case TaskStatus.PACKED:
                    updateFields.picked_at = now;
                    break;
                case TaskStatus.INSPECTING:
                    updateFields.start_inspection_at = now;
                    break;
                case TaskStatus.COMPLETED:
                    updateFields.completed_at = now;
                    break;
            }

            if (operatorId) {
                // Get the staff record to extract the staff_id field value
                try {
                    const staffRecord = await base(STAFF_TABLE).find(operatorId);
                    updateFields.current_operator = staffRecord.get('staff_id') as string; // Use staff_id field value
                } catch (error) {
                    console.error('Error fetching staff record:', error);
                    // Don't fail the entire operation if staff lookup fails
                }
            } else {
                // Explicitly clear the operator field when no operatorId provided
                updateFields.current_operator = '';
            }

            // Use atomic operation if operatorId is provided (for audit logging)
            if (operatorId) {
                const actionType = this.getActionTypeForStatus(status);
                const result = await this.atomicTaskOperation(
                    taskId,
                    operatorId,
                    actionType,
                    updateFields,
                    undefined, // oldValue will be determined by the action context
                    status,
                    `Status updated to ${status}`
                );
                // Invalidate cache after successful update
                invalidateDashboardCache(`Task ${taskId} status updated to ${status}`);
                return result.task;
            } else {
                // Direct update for system operations (no audit needed)
                const record = await base(TASKS_TABLE).update(taskId, updateFields);
                const mappedTask = await this.mapTaskRecord(record);
                // Invalidate cache after successful update
                invalidateDashboardCache(`Task ${taskId} status updated to ${status} (system)`);
                return mappedTask;
            }
        } catch (error) {
            console.error('Error updating task status:', error);
            throw new Error('Failed to update task status');
        }
    }

    async pauseTask(taskId: string, operatorId?: string): Promise<FulfillmentTask | null> {
        try {
            const updateFields: any = {
                is_paused: true,
                current_operator: '', // Clear operator when pausing
                updated_at: new Date().toISOString()
            };

            // Use atomic operation if operatorId is provided
            if (operatorId) {
                const currentTask = await this.getTaskById(taskId);
                const result = await this.atomicTaskOperation(
                    taskId,
                    operatorId,
                    'PAUSE_TASK',
                    updateFields,
                    currentTask?.status,
                    currentTask?.status,
                    'Task paused by operator'
                );
                return result.task;
            } else {
                // Direct update for system operations
                const record = await base(TASKS_TABLE).update(taskId, updateFields);
                return await this.mapTaskRecord(record);
            }
        } catch (error) {
            console.error('Error pausing task:', error);
            throw new Error('Failed to pause task');
        }
    }

    async resumeTask(taskId: string, operatorId: string): Promise<FulfillmentTask | null> {
        try {
            // Get current task status for audit logging
            const currentTask = await this.getTaskById(taskId);
            if (!currentTask) {
                return null;
            }

            const updateFields: any = {
                is_paused: false,
                updated_at: new Date().toISOString()
            };

            // Assign the resuming operator
            if (operatorId) {
                try {
                    const staffRecord = await base(STAFF_TABLE).find(operatorId);
                    updateFields.current_operator = staffRecord.get('staff_id') as string;
                } catch (error) {
                    console.error('Error fetching staff record:', error);
                    // Don't fail the entire operation if staff lookup fails
                }
            }

            // Use atomic operation for resume
            const result = await this.atomicTaskOperation(
                taskId,
                operatorId,
                'RESUME_TASK',
                updateFields,
                'Paused',
                currentTask.status,
                `Task resumed from ${currentTask.status} status`
            );

            return result.task;
        } catch (error) {
            console.error('Error resuming task:', error);
            throw new Error('Failed to resume task');
        }
    }

    async updateTaskChecklist(taskId: string, checklistJson: string): Promise<FulfillmentTask | null> {
        try {
            const record = await base(TASKS_TABLE).update(taskId, {
                checklist_json: checklistJson,
                updated_at: new Date().toISOString()
            });
            return await this.mapTaskRecord(record);
        } catch (error) {
            console.error('Error updating task checklist:', error);
            throw new Error('Failed to update task checklist');
        }
    }

    // MARK: - Staff Operations

    async getAllStaff(): Promise<StaffMember[]> {
        try {
            const records = await base(STAFF_TABLE).select().all();
            return records.map(record => ({
                id: record.get('staff_id') as string, // Use staff_id field instead of record ID
                name: record.get('name') as string
            }));
        } catch (error) {
            console.error('Error fetching staff:', error);
            throw new Error('Failed to fetch staff from Airtable');
        }
    }

    async getStaffById(staffId: string): Promise<StaffMember | null> {
        try {
            // Find staff record by staff_id field value instead of record ID
            const records = await base(STAFF_TABLE)
                .select({
                    filterByFormula: `{staff_id} = '${staffId}'`
                })
                .all();

            if (records.length > 0) {
                const record = records[0];
                return {
                    id: record.get('staff_id') as string,
                    name: record.get('name') as string
                };
            }
            return null;
        } catch (error) {
            console.error('Error fetching staff member:', error);
            return null;
        }
    }

    async createStaff(name: string, staffId?: string): Promise<StaffMember> {
        try {
            const fields: any = {
                name: name,
                is_active: true
            };

            // If staffId is provided, use it, otherwise generate a simple one
            if (staffId) {
                fields.staff_id = staffId;
            } else {
                // Generate a simple staff ID based on name (you can customize this logic)
                const timestamp = Date.now().toString().slice(-4);
                fields.staff_id = `STAFF_${name.toUpperCase().replace(/\s+/g, '_')}_${timestamp}`;
            }

            const record: any = await base(STAFF_TABLE).create(fields);
            return {
                id: record.get('staff_id') as string, // Return staff_id instead of record ID
                name: record.get('name') as string
            };
        } catch (error) {
            console.error('Error creating staff member:', error);
            throw new Error('Failed to create staff member');
        }
    }

    async updateStaff(staffId: string, name: string): Promise<StaffMember | null> {
        try {
            // First find the record by staff_id
            const records = await base(STAFF_TABLE)
                .select({
                    filterByFormula: `{staff_id} = '${staffId}'`
                })
                .all();

            if (records.length === 0) {
                return null;
            }

            const record: any = await base(STAFF_TABLE).update(records[0].id, {
                name: name
            });
            return {
                id: record.get('staff_id') as string,
                name: record.get('name') as string
            };
        } catch (error) {
            console.error('Error updating staff member:', error);
            return null;
        }
    }

    async deleteStaff(staffId: string): Promise<boolean> {
        try {
            // First find the record by staff_id
            const records = await base(STAFF_TABLE)
                .select({
                    filterByFormula: `{staff_id} = '${staffId}'`
                })
                .all();

            if (records.length === 0) {
                return false;
            }

            await base(STAFF_TABLE).destroy(records[0].id);
            return true;
        } catch (error) {
            console.error('Error deleting staff member:', error);
            return false;
        }
    }

    // MARK: - Exception Pool Management

    async moveTaskToExceptionPool(
        taskId: string,
        exceptionReason: string,
        _description: string,
        _reportingOperatorId: string
    ): Promise<void> {
        try {
            const now = new Date().toISOString();

            await base(TASKS_TABLE).update(taskId, {
                status: TaskStatus.PENDING,
                in_exception_pool: true,
                exception_reason: exceptionReason,
                exception_logged_at: now,
                current_operator: '', // Clear current operator
                return_to_pending_at: now,
                updated_at: now
            });

            console.log(`Task ${taskId} moved to exception pool with reason: ${exceptionReason}`);
        } catch (error) {
            console.error('Error moving task to exception pool:', error);
            throw new Error('Failed to move task to exception pool');
        }
    }

    // MARK: - Audit Log

    async getTaskWorkHistory(taskId: string): Promise<any[]> {
        try {
            const records = await base(AUDIT_LOG_TABLE)
                .select({
                    filterByFormula: `{task_id} = '${taskId}'`,
                    sort: [{ field: 'timestamp', direction: 'asc' }]
                })
                .all();

            return await Promise.all(records.map(async (record: any) => {
                const fields = record.fields;

                // Get staff name from linked record
                let operatorName = 'Unknown';
                if (fields.staff_id && Array.isArray(fields.staff_id) && fields.staff_id.length > 0) {
                    try {
                        const staffRecord = await base(STAFF_TABLE).find(fields.staff_id[0]);
                        operatorName = staffRecord.fields.name as string || 'Unknown';
                    } catch (error) {
                        console.error('Error fetching staff name:', error);
                    }
                }

                return {
                    id: record.id,
                    timestamp: fields.timestamp,
                    action: this.formatActionForDisplay(fields.action_type as string, fields.details as string),
                    operatorName: operatorName,
                    icon: this.getActionIcon(fields.action_type as string),
                    details: fields.details || ''
                };
            }));
        } catch (error) {
            console.error('Error fetching task work history:', error);
            throw new Error('Failed to fetch task work history');
        }
    }

    async logAction(
        operatorId: string,
        taskId: string,
        actionType: string,
        oldValue?: string,
        newValue?: string,
        details?: string
    ): Promise<number> {
        try {
            // First validate that the staff member exists
            const staffMember = await this.getStaffById(operatorId);
            if (!staffMember) {
                console.warn(`⚠️  Skipping audit log - Staff member ${operatorId} not found`);
                return 0;
            }

            // Get the next operation sequence for this task
            const nextSequence = await this.getNextOperationSequence(taskId);

            // Map complex action types to simpler ones that exist in Airtable
            const mappedActionType = this.mapActionType(actionType);

            await base(AUDIT_LOG_TABLE).create({
                timestamp: new Date().toISOString(),
                staff_id: [operatorId], // Link to Staff (linked record)
                task_id: taskId, // Single line text
                action_type: mappedActionType,
                old_value: oldValue || '',
                new_value: newValue || '',
                details: `${actionType}: ${details || ''}`.trim(), // Include original action in details
                operation_sequence: nextSequence // Add sequence number
            });

            console.log(`✅ Audit log created: ${actionType} by ${staffMember.name} on task ${taskId} (seq: ${nextSequence})`);
            return nextSequence;
        } catch (error) {
            console.error('❌ Error logging action:', error);
            // Don't throw error for audit logging - it shouldn't break the main operation
            return 0;
        }
    }

    // Helper method to determine action type from status change
    private getActionTypeForStatus(status: TaskStatus): string {
        switch (status) {
            case TaskStatus.PICKING:
                return 'START_PICKING';
            case TaskStatus.PICKED:
                return 'COMPLETE_PICKING';
            case TaskStatus.PACKED:
                return 'START_PACKING';
            case TaskStatus.INSPECTING:
                return 'START_INSPECTION';
            case TaskStatus.COMPLETED:
                return 'COMPLETE_INSPECTION';
            case TaskStatus.CANCELLED:
                return 'CANCEL_TASK';
            case TaskStatus.CORRECTION_NEEDED:
                return 'ENTER_CORRECTION';
            case TaskStatus.CORRECTING:
                return 'START_CORRECTION';
            default:
                return 'FIELD_UPDATED';
        }
    }

    // Helper method to map action types to valid Airtable options
    private mapActionType(actionType: string): string {
        // Map to actual action types that exist in Airtable Audit_Log table
        const actionMappings: { [key: string]: string } = {
            'START_PICKING': 'Tasked_Started',
            'COMPLETE_PICKING': 'Task_Picked',
            'START_PACKING': 'Packing_Started',
            'START_INSPECTION': 'Inspection_Started',
            'COMPLETE_INSPECTION': 'Task_Inspected',
            'ENTER_CORRECTION': 'Inspection_Failed',
            'START_CORRECTION': 'Correction_Started',
            'RESOLVE_CORRECTION': 'Correction_Completed',
            'UPDATE_CHECKLIST': 'Field_Updated',
            'REPORT_EXCEPTION': 'Exception_Logged',
            'REPORT_ISSUE': 'Exception_Logged',
            'CHECK_IN': 'Field_Updated',
            'CHECK_OUT': 'Field_Updated',
            'PAUSE_TASK': 'Task_Paused',
            'RESUME_TASK': 'Task_Resumed',
            'CANCEL_TASK': 'Task_Auto_Cancelled'
        };

        return actionMappings[actionType] || 'Field_Updated';
    }

    // Helper method to format action for display
    private formatActionForDisplay(actionType: string, details: string): string {
        // Extract original action from details if possible
        const originalAction = details.split(':')[0];

        const displayMappings: { [key: string]: string } = {
            'Tasked_Started': 'Task Started',
            'Task_Picked': 'Picking Completed',
            'Packing_Started': 'Packing Completed',
            'Inspection_Started': 'Inspection Started',
            'Task_Inspected': 'Inspection Passed',
            'Inspection_Failed': 'Inspection Failed - Correction Required',
            'Correction_Started': 'Correction Started',
            'Correction_Completed': 'Task Completed via Correction',
            'Field_Updated': 'Updated',
            'Exception_Logged': 'Exception Reported',
            'Task_Paused': 'Task Paused',
            'Task_Resumed': 'Task Resumed',
            'Task_Auto_Cancelled': 'Task Cancelled'
        };

        // Use original action if it's in our mappings, otherwise use the mapped display text
        if (originalAction && originalAction !== actionType) {
            return displayMappings[originalAction] || originalAction.replace('_', ' ');
        }

        return displayMappings[actionType] || actionType.replace('_', ' ');
    }

    // Helper method to get appropriate icon for action
    private getActionIcon(actionType: string): string {
        const iconMappings: { [key: string]: string } = {
            'Tasked_Started': 'play.circle',
            'Task_Picked': 'basket.fill',
            'Packing_Started': 'shippingbox',
            'Inspection_Started': 'magnifyingglass',
            'Task_Inspected': 'checkmark.seal',
            'Inspection_Failed': 'exclamationmark.triangle',
            'Correction_Started': 'wrench',
            'Correction_Completed': 'checkmark.circle.fill',
            'Field_Updated': 'pencil',
            'Exception_Logged': 'exclamationmark.circle',
            'Task_Paused': 'pause.circle',
            'Task_Resumed': 'play.circle',
            'Task_Auto_Cancelled': 'xmark.circle'
        };

        return iconMappings[actionType] || 'circle';
    }

    // MARK: - Helper Methods

    /**
     * Batch version of mapTaskRecord for performance optimization
     * Maps multiple task records using a single sequence query
     */
    private async mapTaskRecords(records: any[]): Promise<FulfillmentTask[]> {
        if (records.length === 0) {
            return [];
        }

        console.log(`📊 BATCH MAPPING: Processing ${records.length} task records`);

        // Extract task IDs and get sequences in batch
        const taskIds = records.map(record => record.id);
        const sequenceMap = await this.getMultipleTaskSequences(taskIds);

        // Map all records using the cached sequences
        const tasks = await Promise.all(
            records.map(record => this.mapTaskRecordWithSequence(record, sequenceMap.get(record.id) || 0))
        );

        console.log(`✅ BATCH MAPPING: Completed mapping ${records.length} tasks`);
        return tasks;
    }

    /**
     * Map a single task record with pre-fetched sequence number
     */
    private async mapTaskRecordWithSequence(record: any, operationSequence: number): Promise<FulfillmentTask> {
        const currentOperatorRaw = record.get('current_operator');

        // Ensure date is properly formatted as ISO8601
        const createdAtRaw = record.get('created_at');
        let createdAtISO: string;
        if (createdAtRaw) {
            // If it's already a Date object, convert to ISO string
            // If it's a string, try to parse and reformat to ensure ISO8601 compatibility
            try {
                createdAtISO = new Date(createdAtRaw).toISOString();
            } catch (error) {
                console.warn('Date parsing failed for:', createdAtRaw, 'using current date');
                createdAtISO = new Date().toISOString();
            }
        } else {
            // Fallback to current date if no created_at
            createdAtISO = new Date().toISOString();
        }

        // Get current operator if exists
        let currentOperator: StaffMember | undefined;
        if (currentOperatorRaw) {
            currentOperator = await this.getOperatorFromStaffId(currentOperatorRaw as string);
        }

        // Extract last modified timestamp for conflict resolution
        const lastModifiedAt = record.get('updated_at') as string;

        return {
            id: record.id,
            orderName: record.get('order_name') as string || '',
            status: record.get('status') as TaskStatus || TaskStatus.PENDING,
            shippingName: record.get('shipping_name') as string || '',
            createdAt: createdAtISO,
            checklistJson: record.get('checklist_json') as string || '[]',
            currentOperator: currentOperator,
            // Pause state
            isPaused: record.get('is_paused') as boolean || false,
            // Exception handling fields
            inExceptionPool: record.get('in_exception_pool') as boolean || false,
            exceptionReason: record.get('exception_reason') as string || undefined,
            exceptionLoggedAt: record.get('exception_logged_at') as string || undefined,
            // Conflict resolution fields
            lastModifiedAt: lastModifiedAt,
            operationSequence: operationSequence // Use pre-fetched sequence
        };
    }

    private async mapTaskRecord(record: any): Promise<FulfillmentTask> {
        const currentOperatorRaw = record.get('current_operator');

        // Ensure date is properly formatted as ISO8601
        const createdAtRaw = record.get('created_at');
        let createdAtISO: string;
        if (createdAtRaw) {
            // If it's already a Date object, convert to ISO string
            // If it's a string, try to parse and reformat to ensure ISO8601 compatibility
            try {
                createdAtISO = new Date(createdAtRaw).toISOString();
            } catch (error) {
                console.warn('Invalid date format for task', record.id, ':', createdAtRaw);
                createdAtISO = new Date().toISOString(); // Fallback to current date
            }
        } else {
            createdAtISO = new Date().toISOString(); // Fallback to current date
        }

        // Resolve current operator if assigned
        let currentOperator: StaffMember | undefined = undefined;
        if (currentOperatorRaw) {
            let staffId: string;
            if (Array.isArray(currentOperatorRaw)) {
                // Handle array format (e.g., ["008"])
                staffId = currentOperatorRaw[0];
            } else {
                // Handle string format (e.g., "008")
                staffId = currentOperatorRaw;
            }
            currentOperator = await this.getOperatorFromStaffId(staffId);
        }


        // Handle lastModifiedAt timestamp for conflict resolution
        const updatedAtRaw = record.get('updated_at');
        let lastModifiedAtISO: string | undefined;
        if (updatedAtRaw) {
            try {
                lastModifiedAtISO = new Date(updatedAtRaw).toISOString();
            } catch (error) {
                console.warn('Invalid lastModifiedAt date format for task', record.id, ':', updatedAtRaw);
                lastModifiedAtISO = new Date().toISOString(); // Fallback to current date
            }
        }

        // Get current operation sequence from audit log
        const operationSequence = await this.getCurrentOperationSequence(record.id);

        return {
            id: record.id,
            orderName: record.get('order_name') as string || '',
            status: record.get('status') as TaskStatus || TaskStatus.PENDING,
            shippingName: record.get('shipping_name') as string || '',
            createdAt: createdAtISO,
            checklistJson: record.get('checklist_json') as string || '[]',
            currentOperator: currentOperator,
            // Pause state
            isPaused: record.get('is_paused') as boolean || false,
            // Exception handling fields
            inExceptionPool: record.get('in_exception_pool') as boolean || false,
            exceptionReason: record.get('exception_reason') as string || undefined,
            exceptionLoggedAt: record.get('exception_logged_at') as string || undefined,
            // Conflict resolution fields
            lastModifiedAt: lastModifiedAtISO,
            operationSequence: operationSequence
        };
    }

    // MARK: - Atomic Operations

    /**
     * Performs an atomic task operation: Audit-first, then task update
     * This ensures sequence is always recorded even if task update fails
     */
    private async atomicTaskOperation(
        taskId: string,
        operatorId: string,
        actionType: string,
        taskUpdate: any,
        oldValue?: string,
        newValue?: string,
        details?: string
    ): Promise<{ task: FulfillmentTask; sequence: number }> {
        // Step 1: Create audit log first (reserves sequence number)
        const sequence = await this.logAction(
            operatorId,
            taskId,
            actionType,
            oldValue,
            newValue,
            details
        );

        // Step 2: Apply task update
        try {
            const record = await base(TASKS_TABLE).update(taskId, taskUpdate);
            const updatedTask = await this.mapTaskRecord(record);

            console.log(`✅ Atomic operation completed: ${actionType} on task ${taskId} (seq: ${sequence})`);
            return { task: updatedTask, sequence };

        } catch (error) {
            // Task update failed - audit log exists but that's OK for data integrity
            console.warn(`⚠️ Task update failed but audit sequence ${sequence} is recorded for ${actionType} on task ${taskId}`);
            console.error('Task update error:', error);
            throw new Error(`Failed to update task: ${error instanceof Error ? error.message : 'Unknown error'}`);
        }
    }

    // MARK: - Operation Sequence Management

    private async getNextOperationSequence(taskId: string): Promise<number> {
        try {
            // Get the highest operation_sequence for this task
            const records = await base(AUDIT_LOG_TABLE)
                .select({
                    filterByFormula: `{task_id} = '${taskId}'`,
                    sort: [{ field: 'operation_sequence', direction: 'desc' }],
                    maxRecords: 1
                })
                .all();

            if (records.length > 0) {
                const latestSequence = records[0].get('operation_sequence') as number;
                return (latestSequence || 0) + 1;
            } else {
                // First operation for this task
                return 1;
            }
        } catch (error) {
            console.error('Error getting next operation sequence:', error);
            // Fallback to timestamp-based sequence
            return Date.now() % 1000000; // Use timestamp as fallback
        }
    }

    async getCurrentOperationSequence(taskId: string): Promise<number> {
        try {
            const records = await base(AUDIT_LOG_TABLE)
                .select({
                    filterByFormula: `{task_id} = '${taskId}'`,
                    sort: [{ field: 'operation_sequence', direction: 'desc' }],
                    maxRecords: 1
                })
                .all();

            if (records.length > 0) {
                return records[0].get('operation_sequence') as number || 0;
            } else {
                return 0; // No operations yet
            }
        } catch (error) {
            console.error('Error getting current operation sequence:', error);
            return 0;
        }
    }

    /**
     * Batch query to get operation sequences for multiple tasks
     * This replaces O(n) individual queries with O(1) batch query
     */
    async getMultipleTaskSequences(taskIds: string[]): Promise<Map<string, number>> {
        const sequenceMap = new Map<string, number>();

        if (taskIds.length === 0) {
            return sequenceMap;
        }

        try {
            // Initialize all tasks with sequence 0
            taskIds.forEach(taskId => sequenceMap.set(taskId, 0));

            // Build OR formula for batch query: OR({task_id} = 'id1', {task_id} = 'id2', ...)
            const taskIdConditions = taskIds.map(taskId => `{task_id} = '${taskId}'`);
            const filterFormula = taskIdConditions.length === 1
                ? taskIdConditions[0]
                : `OR(${taskIdConditions.join(', ')})`;

            console.log(`🔢 BATCH SEQUENCE QUERY: Fetching sequences for ${taskIds.length} tasks`);

            // Fetch all audit log records for these tasks
            const records = await base(AUDIT_LOG_TABLE)
                .select({
                    filterByFormula: filterFormula,
                    sort: [
                        { field: 'task_id', direction: 'asc' },
                        { field: 'operation_sequence', direction: 'desc' }
                    ]
                })
                .all();

            console.log(`🔢 BATCH SEQUENCE QUERY: Retrieved ${records.length} audit records`);

            // Group records by task_id and find the highest sequence for each task
            const taskSequences: { [taskId: string]: number } = {};

            for (const record of records) {
                const taskId = record.get('task_id') as string;
                const sequence = record.get('operation_sequence') as number || 0;

                // Keep only the highest sequence for each task
                if (!taskSequences[taskId] || sequence > taskSequences[taskId]) {
                    taskSequences[taskId] = sequence;
                }
            }

            // Update the map with the found sequences
            Object.entries(taskSequences).forEach(([taskId, sequence]) => {
                sequenceMap.set(taskId, sequence);
            });

            console.log(`✅ BATCH SEQUENCE QUERY: Processed sequences for ${taskIds.length} tasks`);
            return sequenceMap;

        } catch (error) {
            console.error('Error in batch sequence query:', error);
            // Return map with all zeros on error
            return sequenceMap;
        }
    }

    // MARK: - Helper Methods

    private async getOperatorFromStaffId(staffId: string): Promise<StaffMember | undefined> {
        try {
            // Find staff record by staff_id field value
            const records = await base(STAFF_TABLE)
                .select({
                    filterByFormula: `{staff_id} = '${staffId}'`
                })
                .all();

            if (records.length > 0) {
                const record = records[0];
                return {
                    id: record.get('staff_id') as string, // Return staff_id instead of record ID
                    name: record.get('name') as string
                };
            }
        } catch (error) {
            console.error('Error fetching operator from staff_id:', error);
        }
        return undefined;
    }

    // MARK: - Dashboard Helper

    async getTasksGroupedByStatus(): Promise<{
        pending: FulfillmentTask[];
        picking: FulfillmentTask[];
        picked: FulfillmentTask[];
        packed: FulfillmentTask[];
        inspecting: FulfillmentTask[];
        correctionNeeded: FulfillmentTask[];
        correcting: FulfillmentTask[];
        completed: FulfillmentTask[];
        paused: FulfillmentTask[];
        cancelled: FulfillmentTask[];
    }> {
        const allTasks = await this.getAllTasks();

        return {
            pending: allTasks.filter(task => task.status === TaskStatus.PENDING && !task.isPaused),
            picking: allTasks.filter(task => task.status === TaskStatus.PICKING && !task.isPaused),
            picked: allTasks.filter(task => task.status === TaskStatus.PICKED && !task.isPaused),
            packed: allTasks.filter(task => task.status === TaskStatus.PACKED && !task.isPaused),
            inspecting: allTasks.filter(task => task.status === TaskStatus.INSPECTING && !task.isPaused),
            correctionNeeded: allTasks.filter(task => task.status === TaskStatus.CORRECTION_NEEDED && !task.isPaused),
            correcting: allTasks.filter(task => task.status === TaskStatus.CORRECTING && !task.isPaused),
            completed: allTasks.filter(task => task.status === TaskStatus.COMPLETED),
            paused: allTasks.filter(task => task.isPaused === true),
            cancelled: allTasks.filter(task => task.status === TaskStatus.CANCELLED)
        };
    }

    async getTasksGroupedByStatusOptimized(): Promise<{
        grouped: {
            pending: FulfillmentTask[];
            picking: FulfillmentTask[];
            picked: FulfillmentTask[];
            packed: FulfillmentTask[];
            inspecting: FulfillmentTask[];
            correctionNeeded: FulfillmentTask[];
            correcting: FulfillmentTask[];
            completed: FulfillmentTask[];
            paused: FulfillmentTask[];
            cancelled: FulfillmentTask[];
        },
        lastModified: string,
        etag: string
    }> {
        const { tasks, lastModified, etag } = await this.getAllTasksOptimized();

        const grouped = {
            pending: tasks.filter(task => task.status === TaskStatus.PENDING && !task.isPaused),
            picking: tasks.filter(task => task.status === TaskStatus.PICKING && !task.isPaused),
            picked: tasks.filter(task => task.status === TaskStatus.PICKED && !task.isPaused),
            packed: tasks.filter(task => task.status === TaskStatus.PACKED && !task.isPaused),
            inspecting: tasks.filter(task => task.status === TaskStatus.INSPECTING && !task.isPaused),
            correctionNeeded: tasks.filter(task => task.status === TaskStatus.CORRECTION_NEEDED && !task.isPaused),
            correcting: tasks.filter(task => task.status === TaskStatus.CORRECTING && !task.isPaused),
            completed: tasks.filter(task => task.status === TaskStatus.COMPLETED),
            paused: tasks.filter(task => task.isPaused === true),
            cancelled: tasks.filter(task => task.status === TaskStatus.CANCELLED)
        };

        return { grouped, lastModified, etag };
    }
}

// Export singleton instance
export const airtableService = new AirtableService();