import express from 'express';
import { airtableService } from '../services/airtableService';
import { TaskStatus } from '../types';

const router = express.Router();

// GET /api/tasks/:id
// Get detailed task information
router.get('/:id', async (req, res) => {
    try {
        const taskId = req.params.id;
        const task = await airtableService.getTaskById(taskId);

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
        const { taskId, action, operatorId, payload } = req.body;

        if (!taskId || !action) {
            return res.status(400).json({
                success: false,
                error: 'Missing required fields: taskId and action'
            });
        }

        let updatedTask;
        const currentTime = new Date().toISOString();

        switch (action) {
            case 'START_PICKING':
                updatedTask = await airtableService.updateTaskStatus(
                    taskId,
                    TaskStatus.PICKING,
                    operatorId
                );

                // Log the action
                if (operatorId) {
                    await airtableService.logAction(
                        operatorId,
                        taskId,
                        'START_PICKING',
                        'Pending',
                        'Picking',
                        'Started picking process'
                    );
                }
                break;

            case 'COMPLETE_PICKING':
                // Validate payload for weight and dimensions
                if (!payload?.weight || !payload?.dimensions) {
                    return res.status(400).json({
                        success: false,
                        error: 'Weight and dimensions are required for completing picking'
                    });
                }

                updatedTask = await airtableService.updateTaskStatus(
                    taskId,
                    TaskStatus.PACKED,
                    operatorId
                );

                // Log the action
                if (operatorId) {
                    await airtableService.logAction(
                        operatorId,
                        taskId,
                        'COMPLETE_PICKING',
                        'Picking',
                        'Packed',
                        `Completed picking. Weight: ${payload.weight}, Dimensions: ${payload.dimensions}`
                    );
                }
                break;

            case 'START_INSPECTION':
                updatedTask = await airtableService.updateTaskStatus(
                    taskId,
                    TaskStatus.INSPECTING,
                    operatorId
                );

                if (operatorId) {
                    await airtableService.logAction(
                        operatorId,
                        taskId,
                        'START_INSPECTION',
                        'Packed',
                        'Inspecting',
                        'Started quality inspection'
                    );
                }
                break;

            case 'COMPLETE_INSPECTION':
                updatedTask = await airtableService.updateTaskStatus(
                    taskId,
                    TaskStatus.COMPLETED,
                    operatorId
                );

                if (operatorId) {
                    await airtableService.logAction(
                        operatorId,
                        taskId,
                        'COMPLETE_INSPECTION',
                        'Inspecting',
                        'Completed',
                        'Passed quality inspection'
                    );
                }
                break;

            case 'ENTER_CORRECTION':
                // Handle inspection failure and correction
                if (!payload?.errorType || !payload?.notes) {
                    return res.status(400).json({
                        success: false,
                        error: 'Error type and notes are required for corrections'
                    });
                }

                updatedTask = await airtableService.updateTaskStatus(
                    taskId,
                    TaskStatus.PICKING, // Back to picking for correction
                    operatorId
                );

                if (operatorId) {
                    await airtableService.logAction(
                        operatorId,
                        taskId,
                        'ENTER_CORRECTION',
                        'Inspecting',
                        'Picking',
                        `Correction needed: ${payload.errorType} - ${payload.notes}`
                    );
                }
                break;

            case 'REPORT_EXCEPTION':
                if (!payload?.reason) {
                    return res.status(400).json({
                        success: false,
                        error: 'Exception reason is required'
                    });
                }

                // Log exception without changing status
                if (operatorId) {
                    await airtableService.logAction(
                        operatorId,
                        taskId,
                        'REPORT_EXCEPTION',
                        '',
                        '',
                        `Exception reported: ${payload.reason} - ${payload.notes || ''}`
                    );
                }

                updatedTask = await airtableService.getTaskById(taskId);
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
        const taskId = req.params.id;
        const { checklistJson, operatorId } = req.body;

        if (!checklistJson) {
            return res.status(400).json({
                success: false,
                error: 'checklistJson is required'
            });
        }

        const updatedTask = await airtableService.updateTaskChecklist(taskId, checklistJson);

        if (!updatedTask) {
            return res.status(404).json({
                success: false,
                error: 'Task not found'
            });
        }

        // Log checklist update
        if (operatorId) {
            await airtableService.logAction(
                operatorId,
                taskId,
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