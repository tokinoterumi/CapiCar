export interface FulfillmentTask {
    id: string;
    orderName: string;
    status: TaskStatus;
    shippingName: string;
    createdAt: string;
    checklistJson: string;
    currentOperator?: StaffMember;
}

export interface StaffMember {
    id: string;
    name: string;
}

export enum TaskStatus {
    PENDING = 'Pending',
    PICKING = 'Picking',
    PACKED = 'Packed',
    INSPECTING = 'Inspecting',
    COMPLETED = 'Completed',
    PAUSED = 'Paused',
    CANCELLED = 'Cancelled'
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