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

            return Promise.all(records.map(record => this.mapTaskRecord(record)));
        } catch (error) {
            console.error('Error fetching tasks:', error);
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
            return await this.mapTaskRecord(record);
        } catch (error) {
            console.error('Error updating task status:', error);
            throw new Error('Failed to update task status');
        }
    }

    async pauseTask(taskId: string): Promise<FulfillmentTask | null> {
        try {
            const updateFields: any = {
                is_paused: true,
                current_operator: '', // Clear operator when pausing
                updated_at: new Date().toISOString()
            };

            const record = await base(TASKS_TABLE).update(taskId, updateFields);
            return await this.mapTaskRecord(record);
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
                throw new Error('Task not found');
            }

            const updateFields: any = {
                is_paused: false,
                updated_at: new Date().toISOString()
            };

            // Assign the resuming operator
            if (operatorId) {
                try {
                    const staffRecord = await base(STAFF_TABLE).find(operatorId);
                    const staffId = staffRecord.get('staff_id') as string;
                    updateFields.current_operator = staffId;
                } catch (error) {
                    console.error('Error fetching staff record:', error);
                    // Don't fail the entire operation if staff lookup fails
                }
            }

            const record = await base(TASKS_TABLE).update(taskId, updateFields);
            const updatedTask = await this.mapTaskRecord(record);

            // Log the resume action
            if (operatorId && updatedTask) {
                await this.logAction(
                    operatorId,
                    taskId,
                    'RESUME_TASK',
                    'Paused',
                    updatedTask.status,
                    `Task resumed from ${updatedTask.status} status`
                );
            }

            return updatedTask;
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

    async createStaff(name: string, staffId?: string): Promise<StaffMember> {
        try {
            const fields: any = {
                name: name,
                is_active: true
            };

            // If staffId is provided, use it, otherwise let Airtable auto-generate
            if (staffId) {
                fields.staff_id = staffId;
            }

            const record: any = await base(STAFF_TABLE).create(fields);
            return {
                id: record.id,
                name: record.fields.name as string
            };
        } catch (error) {
            console.error('Error creating staff member:', error);
            throw new Error('Failed to create staff member');
        }
    }

    async updateStaff(staffId: string, name: string): Promise<StaffMember | null> {
        try {
            const record: any = await base(STAFF_TABLE).update(staffId, {
                name: name
            });
            return {
                id: record.id,
                name: record.fields.name as string
            };
        } catch (error) {
            console.error('Error updating staff member:', error);
            return null;
        }
    }

    async deleteStaff(staffId: string): Promise<boolean> {
        try {
            await base(STAFF_TABLE).destroy(staffId);
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
    ): Promise<void> {
        try {
            // First validate that the staff member exists
            const staffMember = await this.getStaffById(operatorId);
            if (!staffMember) {
                console.warn(`⚠️  Skipping audit log - Staff member ${operatorId} not found`);
                return;
            }

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

            console.log(`✅ Audit log created: ${actionType} by ${staffMember.name} on task ${taskId}`);
        } catch (error) {
            console.error('❌ Error logging action:', error);
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
            exceptionLoggedAt: record.get('exception_logged_at') as string || undefined
        };
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
                    id: record.id, // Return Airtable record ID
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
}

// Export singleton instance
export const airtableService = new AirtableService();