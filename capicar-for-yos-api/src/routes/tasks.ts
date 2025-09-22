import express from 'express';
import { airtableService } from '../services/airtableService';
import { TaskStatus, TaskAction } from '../types';

const router = express.Router();

// GET /api/tasks/:id
// Get detailed task information
router.get('/:id', async (req, res) => {
    try {
        const task_id = req.params.id;
        const task = await airtableService.getTaskById(task_id);

        if (!task) {
            return res.status(404).json({
                success: false,
                error: 'Task not found'
            });
        }

        // Add conflict resolution headers for debugging
        res.setHeader('X-Last-Modified', task.lastModifiedAt || 'unknown');
        res.setHeader('X-Server-Timestamp', new Date().toISOString());
        res.setHeader('X-Operation-Sequence', task.operationSequence?.toString() || '0');

        res.json({
            success: true,
            data: task
        });

    } catch (error) {
        console.error('Get task error:', error);
        res.status(500).json({
            success: false,
            error: 'Failed to fetch task',
            message: error instanceof Error ? error.message : 'Unknown error'
        });
    }
});

// POST /api/tasks/action
// Handle task status transitions and actions
router.post('/action', async (req, res) => {
    try {
        const { task_id, action, operator_id, payload } = req.body;

        console.log('DEBUG: Task action request body:', JSON.stringify(req.body, null, 2));
        console.log('DEBUG: task_id exists:', !!task_id);
        console.log('DEBUG: action exists:', !!action);
        console.log('DEBUG: operator_id exists:', !!operator_id);

        if (!task_id || !action) {
            return res.status(400).json({
                success: false,
                error: 'Missing required fields: task_id and action'
            });
        }

        let updatedTask;
        const currentTime = new Date().toISOString();

        switch (action) {
            case TaskAction.START_PICKING:
                updatedTask = await airtableService.updateTaskStatus(
                    task_id,
                    TaskStatus.PICKING,
                    operator_id
                );
                break;

            case TaskAction.COMPLETE_PICKING:
                updatedTask = await airtableService.updateTaskStatus(
                    task_id,
                    TaskStatus.PICKED,
                    operator_id
                );
                break;

            case TaskAction.START_PACKING:
                // Validate payload for weight and dimensions
                if (!payload?.weight || !payload?.dimensions) {
                    return res.status(400).json({
                        success: false,
                        error: 'Weight and dimensions are required for starting packing'
                    });
                }

                // Clear operator when transitioning to packed - task becomes available for any inspector
                updatedTask = await airtableService.updateTaskStatus(
                    task_id,
                    TaskStatus.PACKED
                    // No operator_id - clears the current_operator field
                );

                // Log the action manually since we need to clear the operator
                if (operator_id) {
                    await airtableService.logAction(
                        operator_id,
                        task_id,
                        TaskAction.START_PACKING,
                        TaskStatus.PICKED,
                        TaskStatus.PACKED,
                        `Started packing. Weight: ${payload.weight}, Dimensions: ${payload.dimensions}`
                    );
                }
                break;

            case TaskAction.START_INSPECTION:
                updatedTask = await airtableService.updateTaskStatus(
                    task_id,
                    TaskStatus.INSPECTING,
                    operator_id
                );
                break;

            case TaskAction.COMPLETE_INSPECTION_CRITERIA:
                // Transition to inspected state when all required criteria are met
                updatedTask = await airtableService.updateTaskStatus(
                    task_id,
                    TaskStatus.INSPECTED,
                    operator_id
                );
                break;

            case TaskAction.COMPLETE_INSPECTION:
                updatedTask = await airtableService.updateTaskStatus(
                    task_id,
                    TaskStatus.COMPLETED,
                    operator_id
                );
                break;

            case TaskAction.ENTER_CORRECTION:
                // Handle inspection failure and correction
                if (!payload?.errorType) {
                    return res.status(400).json({
                        success: false,
                        error: 'Error type is required for corrections'
                    });
                }

                updatedTask = await airtableService.updateTaskStatus(
                    task_id,
                    TaskStatus.CORRECTION_NEEDED,
                    operator_id
                );
                break;

            case TaskAction.START_CORRECTION:
                updatedTask = await airtableService.updateTaskStatus(
                    task_id,
                    TaskStatus.CORRECTING,
                    operator_id
                );
                break;

            case TaskAction.RESOLVE_CORRECTION:
                // Complete the task directly - no need for further inspection after correction
                updatedTask = await airtableService.updateTaskStatus(
                    task_id,
                    TaskStatus.COMPLETED,
                    operator_id
                );
                break;

            case TaskAction.PAUSE_TASK:
                // Use atomic pause method that handles audit logging
                updatedTask = await airtableService.pauseTask(task_id, operator_id);
                break;

            case TaskAction.CANCEL_TASK:
                updatedTask = await airtableService.updateTaskStatus(
                    task_id,
                    TaskStatus.CANCELLED,
                    operator_id
                );
                break;

            case TaskAction.REPORT_EXCEPTION:
                if (!payload?.reason) {
                    return res.status(400).json({
                        success: false,
                        error: 'Exception reason is required'
                    });
                }

                // Log exception without changing status
                if (operator_id) {
                    await airtableService.logAction(
                        operator_id,
                        task_id,
                        TaskAction.REPORT_EXCEPTION,
                        '',
                        '',
                        `Exception reported: ${payload.reason} - ${payload.notes || ''}`
                    );
                }

                updatedTask = await airtableService.getTaskById(task_id);
                break;

            case TaskAction.RESUME_TASK:
                if (!operator_id) {
                    return res.status(400).json({
                        success: false,
                        error: 'Operator ID is required for resuming tasks'
                    });
                }

                updatedTask = await airtableService.resumeTask(task_id, operator_id);
                break;

            default:
                return res.status(400).json({
                    success: false,
                    error: `Unknown action: ${action}`
                });
        }

        if (!updatedTask) {
            return res.status(404).json({
                success: false,
                error: 'Task not found or update failed'
            });
        }

        // Add conflict resolution headers for debugging
        res.setHeader('X-Last-Modified', updatedTask.lastModifiedAt || 'unknown');
        res.setHeader('X-Server-Timestamp', currentTime);
        res.setHeader('X-Action-Performed', action);
        res.setHeader('X-Operation-Sequence', updatedTask.operationSequence?.toString() || '0');

        res.json({
            success: true,
            data: updatedTask,
            action: action,
            timestamp: currentTime
        });

    } catch (error) {
        console.error('Task action error:', error);
        res.status(500).json({
            success: false,
            error: 'Failed to perform task action',
            message: error instanceof Error ? error.message : 'Unknown error'
        });
    }
});

// PUT /api/tasks/:id/checklist
// Update task checklist (for barcode scanning results)
router.put('/:id/checklist', async (req, res) => {
    try {
        const task_id = req.params.id;
        const { checklist_json, operator_id } = req.body;

        console.log('DEBUG: Checklist update request body:', JSON.stringify(req.body, null, 2));
        console.log('DEBUG: checklist_json exists:', !!checklist_json);
        console.log('DEBUG: operator_id exists:', !!operator_id);

        if (!checklist_json) {
            return res.status(400).json({
                success: false,
                error: 'checklist_json is required'
            });
        }

        const updatedTask = await airtableService.updateTaskChecklist(task_id, checklist_json);

        if (!updatedTask) {
            return res.status(404).json({
                success: false,
                error: 'Task not found'
            });
        }

        // Log checklist update
        if (operator_id) {
            await airtableService.logAction(
                operator_id,
                task_id,
                'UPDATE_CHECKLIST',
                '',
                '',
                'Updated task checklist'
            );
        }

        res.json({
            success: true,
            data: updatedTask
        });

    } catch (error) {
        console.error('Update checklist error:', error);
        res.status(500).json({
            success: false,
            error: 'Failed to update checklist',
            message: error instanceof Error ? error.message : 'Unknown error'
        });
    }
});

// GET /api/tasks/:id/history
// Get work history/audit log for a specific task
router.get('/:id/history', async (req, res) => {
    try {
        const task_id = req.params.id;

        const workHistory = await airtableService.getTaskWorkHistory(task_id);

        res.json({
            success: true,
            data: workHistory
        });

    } catch (error) {
        console.error('Get task history error:', error);
        res.status(500).json({
            success: false,
            error: 'Failed to fetch task history',
            message: error instanceof Error ? error.message : 'Unknown error'
        });
    }
});

export default router;