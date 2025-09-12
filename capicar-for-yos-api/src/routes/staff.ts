import express from 'express';
import { airtableService } from '../services/airtableService';

const router = express.Router();

// GET /api/staff
// Get all staff members for operator selection
router.get('/', async (req, res) => {
    try {
        const staff = await airtableService.getAllStaff();

        res.json({
            success: true,
            data: staff
        });

    } catch (error) {
        console.error('Get staff error:', error);
        res.status(500).json({
            success: false,
            error: 'Failed to fetch staff',
            message: error instanceof Error ? error.message : 'Unknown error'
        });
    }
});

// GET /api/staff/:id
// Get specific staff member details
router.get('/:id', async (req, res) => {
    try {
        const staffId = req.params.id;
        const staff = await airtableService.getStaffById(staffId);

        if (!staff) {
            return res.status(404).json({
                success: false,
                error: 'Staff member not found'
            });
        }

        res.json({
            success: true,
            data: staff
        });

    } catch (error) {
        console.error('Get staff member error:', error);
        res.status(500).json({
            success: false,
            error: 'Failed to fetch staff member',
            message: error instanceof Error ? error.message : 'Unknown error'
        });
    }
});

// POST /api/staff/checkin
// Handle operator check-in for shift management
router.post('/checkin', async (req, res) => {
    try {
        const { staffId, action } = req.body;

        if (!staffId || !action) {
            return res.status(400).json({
                success: false,
                error: 'Missing required fields: staffId and action'
            });
        }

        // Verify staff member exists
        const staff = await airtableService.getStaffById(staffId);
        if (!staff) {
            return res.status(404).json({
                success: false,
                error: 'Staff member not found'
            });
        }

        const currentTime = new Date().toISOString();

        switch (action) {
            case 'CHECK_IN':
                // Log check-in action
                await airtableService.logAction(
                    staffId,
                    '', // No specific task for check-in
                    'CHECK_IN',
                    '',
                    '',
                    'Operator checked in for shift'
                );

                res.json({
                    success: true,
                    data: {
                        staff: staff,
                        action: 'CHECK_IN',
                        timestamp: currentTime,
                        message: `${staff.name} checked in successfully`
                    }
                });
                break;

            case 'CHECK_OUT':
                // Log check-out action
                await airtableService.logAction(
                    staffId,
                    '', // No specific task for check-out
                    'CHECK_OUT',
                    '',
                    '',
                    'Operator checked out from shift'
                );

                res.json({
                    success: true,
                    data: {
                        staff: staff,
                        action: 'CHECK_OUT',
                        timestamp: currentTime,
                        message: `${staff.name} checked out successfully`
                    }
                });
                break;

            default:
                return res.status(400).json({
                    success: false,
                    error: `Unknown check-in action: ${action}`
                });
        }

    } catch (error) {
        console.error('Staff check-in error:', error);
        res.status(500).json({
            success: false,
            error: 'Failed to process check-in',
            message: error instanceof Error ? error.message : 'Unknown error'
        });
    }
});

export default router;