import express from 'express';
import { airtableService } from '../services/airtableService';

const router = express.Router();

// GET /api/dashboard
// Returns dashboard data in the format the Swift client's `DashboardData` model expects.
router.get('/', async (req, res) => {
    try {
        // Check for conditional requests (If-None-Match header)
        const clientETag = req.get('If-None-Match');

        // 1. Fetch the actual tasks from the database with optimized caching
        const { grouped: granularGroupedTasks, lastModified, etag } = await airtableService.getTasksGroupedByStatusOptimized();

        // If client has current data, return 304 Not Modified
        if (clientETag && clientETag === etag) {
            console.log('📦 HTTP CACHE HIT: Client has current data, returning 304');
            res.status(304).end();
            return;
        }

        console.log('🔄 HTTP CACHE MISS: Generating fresh response');

        // 2. Transform granular groups into simplified user-friendly groups
        const simplifiedGroupedTasks = {
            pending: granularGroupedTasks.pending,
            picking: [
                ...granularGroupedTasks.picking,
                ...granularGroupedTasks.picked
            ],
            packed: granularGroupedTasks.packed,
            inspecting: [
                ...granularGroupedTasks.inspecting,
                ...granularGroupedTasks.correctionNeeded,
                ...granularGroupedTasks.correcting
            ],
            completed: granularGroupedTasks.completed,
            paused: granularGroupedTasks.paused,
            cancelled: granularGroupedTasks.cancelled
        };

        // 3. Calculate dashboard statistics from simplified groups
        const stats = {
            pending: simplifiedGroupedTasks.pending.length,
            picking: simplifiedGroupedTasks.picking.length,
            packed: simplifiedGroupedTasks.packed.length,
            inspecting: simplifiedGroupedTasks.inspecting.length,
            completed: simplifiedGroupedTasks.completed.length,
            paused: simplifiedGroupedTasks.paused.length,
            cancelled: simplifiedGroupedTasks.cancelled.length,
            total: Object.values(simplifiedGroupedTasks).reduce((sum, tasks) => sum + tasks.length, 0)
        };

        // 4. Create the dashboard data structure that matches Swift DashboardData
        const dashboardData = {
            tasks: simplifiedGroupedTasks,
            stats: stats,
            lastUpdated: lastModified
        };

        // Set caching headers
        res.setHeader('ETag', etag);
        res.setHeader('Last-Modified', new Date(lastModified).toUTCString());
        res.setHeader('Cache-Control', 'private, must-revalidate, max-age=0');

        // Add conflict resolution headers for debugging
        res.setHeader('X-Server-Timestamp', new Date().toISOString());
        res.setHeader('X-Dashboard-Generated', lastModified);

        // 5. Send the response in the format iOS app expects
        res.json({
            success: true,
            data: dashboardData
        });

    } catch (error) {
        console.error('Dashboard error:', error);
        // In case of an error, send a standard error response.
        res.status(500).json({
            success: false,
            error: 'Failed to fetch dashboard data',
            message: error instanceof Error ? error.message : 'Unknown error'
        });
    }
});

export default router;
