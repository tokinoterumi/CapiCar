export interface FulfillmentTask {
    id: string;
    orderName: string;
    status: TaskStatus;
    shippingName: string;
    createdAt: string;
    checklistJson: string;
    currentOperator?: StaffMember;
    // Shipping address fields
    shippingAddress1?: string;
    shippingAddress2?: string;
    shippingCity?: string;
    shippingProvince?: string;
    shippingZip?: string;
    shippingPhone?: string;
    // Pause state
    isPaused?: boolean;
    // Exception handling fields
    inExceptionPool?: boolean;
    exceptionReason?: string;
    exceptionLoggedAt?: string;
    // Conflict resolution fields
    lastModifiedAt?: string; // ISO8601 timestamp for conflict resolution
    operationSequence?: number; // Operation sequence number from audit log
}

export interface StaffMember {
    id: string;
    name: string;
}

export enum TaskStatus {
    PENDING = 'Pending',
    PICKING = 'Picking',
    PICKED = 'Picked',
    PACKED = 'Packed',
    INSPECTING = 'Inspecting',
    INSPECTED = 'Inspected',
    CORRECTION_NEEDED = 'Correction_Needed',
    CORRECTING = 'Correcting',
    COMPLETED = 'Completed',
    CANCELLED = 'Cancelled'
}

export enum TaskAction {
    START_PICKING = 'START_PICKING',
    COMPLETE_PICKING = 'COMPLETE_PICKING',
    START_PACKING = 'START_PACKING',
    START_INSPECTION = 'START_INSPECTION',
    COMPLETE_INSPECTION_CRITERIA = 'COMPLETE_INSPECTION_CRITERIA',
    COMPLETE_INSPECTION = 'COMPLETE_INSPECTION',
    ENTER_CORRECTION = 'ENTER_CORRECTION',
    START_CORRECTION = 'START_CORRECTION',
    RESOLVE_CORRECTION = 'RESOLVE_CORRECTION',
    REPORT_EXCEPTION = 'REPORT_EXCEPTION',
    PAUSE_TASK = 'PAUSE_TASK',
    RESUME_TASK = 'RESUME_TASK',
    CANCEL_TASK = 'CANCEL_TASK'
}

export interface ChecklistItem {
    id: number;
    sku: string;
    name: string;
    variant_title: string;
    quantity_required: number;
    image_url?: string;
    quantity_picked?: number;
    is_completed?: boolean;
}