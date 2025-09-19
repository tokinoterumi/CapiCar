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

            return records.map(record => this.mapTaskRecord(record));
        } catch (error) {
            console.error('Error fetching tasks:', error);
            throw new Error('Failed to fetch tasks from Airtable');
        }
    }

    async getTaskById(taskId: string): Promise<FulfillmentTask | null> {
        try {
            const record = await base(TASKS_TABLE).find(taskId);
            return this.mapTaskRecord(record);
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
                    const staffId = staffRecord.get('staff_id') as string;
                    updateFields.current_operator = staffId; // Use staff_id field value
                } catch (error) {
                    console.error('Error fetching staff record:', error);
                    // Don't fail the entire operation if staff lookup fails
                }
            } else {
                // Explicitly clear the operator field when no operatorId provided
                updateFields.current_operator = '';
            }

            const record = await base(TASKS_TABLE).update(taskId, updateFields);
            return this.mapTaskRecord(record);
        } catch (error) {
            console.error('Error updating task status:', error);
            throw new Error('Failed to update task status');
        }
    }

    async updateTaskChecklist(taskId: string, checklistJson: string): Promise<FulfillmentTask | null> {
        try {
            const record = await base(TASKS_TABLE).update(taskId, {
                checklist_json: checklistJson,
                updated_at: new Date().toISOString()
            });
            return this.mapTaskRecord(record);
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
                id: record.id,
                name: record.get('name') as string
            }));
        } catch (error) {
            console.error('Error fetching staff:', error);
            throw new Error('Failed to fetch staff from Airtable');
        }
    }

    async getStaffById(staffId: string): Promise<StaffMember | null> {
        try {
            const record = await base(STAFF_TABLE).find(staffId);
            return {
                id: record.id,
                name: record.get('name') as string
            };
        } catch (error) {
            console.error('Error fetching staff member:', error);
            return null;
        }
    }

    // MARK: - Exception Pool Management

    async moveTaskToExceptionPool(
        taskId: string,
        exceptionReason: string,
        description: string,
        reportingOperatorId: string
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

    async logAction(
        operatorId: string,
        taskId: string,
        actionType: string,
        oldValue?: string,
        newValue?: string,
        details?: string
    ): Promise<void> {
        try {
            // Map complex action types to simpler ones that exist in Airtable
            const mappedActionType = this.mapActionType(actionType);

            await base(AUDIT_LOG_TABLE).create({
                timestamp: new Date().toISOString(),
                staff_id: [operatorId], // Link to Staff (linked record)
                task_id: taskId, // Single line text
                action_type: mappedActionType,
                old_value: oldValue || '',
                new_value: newValue || '',
                details: `${actionType}: ${details || ''}`.trim() // Include original action in details
            });
        } catch (error) {
            console.error('Error logging action:', error);
            // Don't throw error for audit logging - it shouldn't break the main operation
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
            'CANCEL_TASK': 'Task_Auto_Cancelled'
        };

        return actionMappings[actionType] || 'Field_Updated';
    }

    // MARK: - Helper Methods

    private mapTaskRecord(record: any): FulfillmentTask {
        const currentOperatorArray = record.get('current_operator') as string[];

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

        return {
            id: record.id,
            orderName: record.get('order_name') as string || '',
            status: record.get('status') as TaskStatus || TaskStatus.PENDING,
            shippingName: record.get('shipping_name') as string || '',
            createdAt: createdAtISO,
            checklistJson: record.get('checklist_json') as string || '[]',
            currentOperator: currentOperatorArray && currentOperatorArray.length > 0
                ? { id: currentOperatorArray[0], name: 'Loading...' } // We'll need to fetch name separately
                : undefined,
            // Exception handling fields
            inExceptionPool: record.get('in_exception_pool') as boolean || false,
            exceptionReason: record.get('exception_reason') as string || undefined,
            exceptionLoggedAt: record.get('exception_logged_at') as string || undefined
        };
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
            pending: allTasks.filter(task => task.status === TaskStatus.PENDING),
            picking: allTasks.filter(task => task.status === TaskStatus.PICKING),
            picked: allTasks.filter(task => task.status === TaskStatus.PICKED),
            packed: allTasks.filter(task => task.status === TaskStatus.PACKED),
            inspecting: allTasks.filter(task => task.status === TaskStatus.INSPECTING),
            correctionNeeded: allTasks.filter(task => task.status === TaskStatus.CORRECTION_NEEDED),
            correcting: allTasks.filter(task => task.status === TaskStatus.CORRECTING),
            completed: allTasks.filter(task => task.status === TaskStatus.COMPLETED),
            paused: allTasks.filter(task => task.status === TaskStatus.PAUSED),
            cancelled: allTasks.filter(task => task.status === TaskStatus.CANCELLED)
        };
    }
}

// Export singleton instance
export const airtableService = new AirtableService();