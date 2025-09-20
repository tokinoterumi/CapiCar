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

                // Log the action
                if (operator_id) {
                    await airtableService.logAction(
                        operator_id,
                        task_id,
                        'START_PICKING',
                        'Pending',
                        'Picking',
                        'Started picking process'
                    );
                }
                break;

            case TaskAction.COMPLETE_PICKING:
                updatedTask = await airtableService.updateTaskStatus(
                    task_id,
                    TaskStatus.PICKED,
                    operator_id
                );

                // Log the action
                if (operator_id) {
                    await airtableService.logAction(
                        operator_id,
                        task_id,
                        TaskAction.COMPLETE_PICKING,
                        TaskStatus.PICKING,
                        TaskStatus.PICKED,
                        'Completed picking process'
                    );
                }
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

                // Log the action
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

                if (operator_id) {
                    await airtableService.logAction(
                        operator_id,
                        task_id,
                        TaskAction.START_INSPECTION,
                        TaskStatus.PACKED,
                        TaskStatus.INSPECTING,
                        'Started quality inspection'
                    );
                }
                break;

            case TaskAction.COMPLETE_INSPECTION_CRITERIA:
                // Transition to inspected state when all required criteria are met
                updatedTask = await airtableService.updateTaskStatus(
                    task_id,
                    TaskStatus.INSPECTED,
                    operator_id
                );

                if (operator_id) {
                    await airtableService.logAction(
                        operator_id,
                        task_id,
                        TaskAction.COMPLETE_INSPECTION_CRITERIA,
                        TaskStatus.INSPECTING,
                        TaskStatus.INSPECTED,
                        'Completed all required inspection criteria'
                    );
                }
                break;

            case TaskAction.COMPLETE_INSPECTION:
                updatedTask = await airtableService.updateTaskStatus(
                    task_id,
                    TaskStatus.COMPLETED,
                    operator_id
                );

                if (operator_id) {
                    await airtableService.logAction(
                        operator_id,
                        task_id,
                        TaskAction.COMPLETE_INSPECTION,
                        TaskStatus.INSPECTED,
                        TaskStatus.COMPLETED,
                        'Passed quality inspection'
                    );
                }
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

                if (operator_id) {
                    // Get the current task to determine the previous status
                    const currentTask = await airtableService.getTaskById(task_id);
                    const previousStatus = currentTask?.status || TaskStatus.INSPECTING;

                    await airtableService.logAction(
                        operator_id,
                        task_id,
                        TaskAction.ENTER_CORRECTION,
                        previousStatus,
                        TaskStatus.CORRECTION_NEEDED,
                        `Correction needed: ${payload.errorType}${payload.notes ? ' - ' + payload.notes : ''}`
                    );
                }
                break;

            case TaskAction.START_CORRECTION:
                updatedTask = await airtableService.updateTaskStatus(
                    task_id,
                    TaskStatus.CORRECTING,
                    operator_id
                );

                if (operator_id) {
                    await airtableService.logAction(
                        operator_id,
                        task_id,
                        TaskAction.START_CORRECTION,
                        TaskStatus.CORRECTION_NEEDED,
                        TaskStatus.CORRECTING,
                        'Started correction process'
                    );
                }
                break;

            case TaskAction.RESOLVE_CORRECTION:
                // Determine where to go after correction based on error type
                const targetStatus = payload?.errorType === 'PICKING_ERROR' ? TaskStatus.PICKED : TaskStatus.PACKED;
                
                updatedTask = await airtableService.updateTaskStatus(
                    task_id,
                    targetStatus,
                    operator_id
                );

                if (operator_id) {
                    await airtableService.logAction(
                        operator_id,
                        task_id,
                        TaskAction.RESOLVE_CORRECTION,
                        TaskStatus.CORRECTING,
                        targetStatus,
                        `Resolved correction${payload?.newTrackingNumber ? '. New tracking: ' + payload.newTrackingNumber : ''}`
                    );
                }
                break;

            case TaskAction.PAUSE_TASK:
                // Use new pause method that preserves status but sets is_paused flag
                updatedTask = await airtableService.pauseTask(task_id);

                if (operator_id && updatedTask) {
                    await airtableService.logAction(
                        operator_id,
                        task_id,
                        TaskAction.PAUSE_TASK,
                        updatedTask.status,
                        updatedTask.status,
                        'Task paused by operator'
                    );
                }
                break;

            case TaskAction.CANCEL_TASK:
                updatedTask = await airtableService.updateTaskStatus(
                    task_id,
                    TaskStatus.CANCELLED,
                    operator_id
                );

                if (operator_id) {
                    await airtableService.logAction(
                        operator_id,
                        task_id,
                        TaskAction.CANCEL_TASK,
                        '',
                        TaskStatus.CANCELLED,
                        'Task cancelled by operator'
                    );
                }
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

export default router;