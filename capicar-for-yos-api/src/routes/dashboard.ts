import express from 'express';
import { airtableService } from '../services/airtableService';

const router = express.Router();

// GET /api/dashboard
// Returns grouped tasks in the exact format the Swift client's `GroupedTasks` model expects.
router.get('/', async (req, res) => {
    try {
        // 1. Define the complete, default structure that the Swift client requires.
        // This ensures all keys are present, even if the database has no tasks for a certain status.
        const defaultGroupedTasks = {
            pending: [],
            picking: [],
            packed: [],
            inspecting: [],
            completed: [],
            paused: [],
            cancelled: []
        };

        // 2. Fetch the actual tasks from the database.
        const actualGroupedTasks = await airtableService.getTasksGroupedByStatus();

        // 3. Merge the actual tasks into the default structure.
        // The spread syntax (`...`) safely overrides the empty arrays in `defaultGroupedTasks`
        // with the actual tasks from the database, while keeping any missing keys.
        const finalGroupedTasks = {
            ...defaultGroupedTasks,
            ...actualGroupedTasks
        };

        // 4. Send the final, correctly-structured object directly as the response.
        // This now perfectly matches the Swift `GroupedTasks` Codable struct.
        res.json(finalGroupedTasks);

    } catch (error) {
        console.error('Dashboard error:', error);
        // In case of an error, send a standard error response.
        res.status(500).json({
            error: 'Failed to fetch dashboard data',
            message: error instanceof Error ? error.message : 'Unknown error'
        });
    }
});

export default router;
