-- Azure SQL Database Schema for Change Impact Analysis System
-- Created: 2026-09-03

-- Enable change tracking for audit purposes
ALTER DATABASE [CIA-Database] SET CHANGE_TRACKING = ON (CHANGE_RETENTION = 10 DAYS, AUTO_CLEANUP = ON);

-- ============================================================================
-- TABLES
-- ============================================================================

-- Source systems that feed into the CIA workflow
CREATE TABLE dbo.SourceSystems (
    SourceSystemId INT PRIMARY KEY IDENTITY(1,1),
    SystemName VARCHAR(100) NOT NULL UNIQUE,
    SystemCode VARCHAR(20) NOT NULL UNIQUE,
    Description NVARCHAR(500),
    IsActive BIT DEFAULT 1,
    CreatedAt DATETIME2 DEFAULT GETUTCDATE(),
    ModifiedAt DATETIME2 DEFAULT GETUTCDATE()
);

-- Changes detected from source systems
CREATE TABLE dbo.Changes (
    ChangeId VARCHAR(100) PRIMARY KEY,
    SourceSystemId INT NOT NULL FOREIGN KEY REFERENCES dbo.SourceSystems(SourceSystemId),
    ChangeType VARCHAR(50), -- CREATE, UPDATE, DELETE
    ChangeData NVARCHAR(MAX) NOT NULL, -- JSON payload
    ExternalId VARCHAR(255), -- Source system's native ID
    DetectedAt DATETIME2 NOT NULL,
    ProcessedAt DATETIME2,
    IsProcessed BIT DEFAULT 0,
    CreatedAt DATETIME2 DEFAULT GETUTCDATE()
);

-- Change Impact Analysis records
CREATE TABLE dbo.ChangeImpactAnalysis (
    CiaId VARCHAR(100) PRIMARY KEY,
    ChangeId VARCHAR(100) NOT NULL UNIQUE FOREIGN KEY REFERENCES dbo.Changes(ChangeId),
    AiModel VARCHAR(50) NOT NULL, -- e.g., 'v2.1'
    AiConfidence FLOAT NOT NULL, -- 0.0 to 1.0
    ExecutionTimeMs INT NOT NULL,
    ComputedAt DATETIME2 NOT NULL,
    ComputedByService VARCHAR(100), -- Container instance ID or function name
    ImpactedItemCount INT DEFAULT 0,
    CreatedAt DATETIME2 DEFAULT GETUTCDATE()
);

-- Items impacted by a change
CREATE TABLE dbo.ImpactedItems (
    ImpactedItemId BIGINT PRIMARY KEY IDENTITY(1,1),
    CiaId VARCHAR(100) NOT NULL FOREIGN KEY REFERENCES dbo.ChangeImpactAnalysis(CiaId),
    ItemId VARCHAR(255) NOT NULL,
    ItemType VARCHAR(50), -- e.g., 'BillingCode', 'Customer'
    ImpactLevel VARCHAR(20) NOT NULL CHECK (ImpactLevel IN ('high', 'medium', 'low')),
    ImpactDescription NVARCHAR(MAX),
    AffectedSystems NVARCHAR(MAX), -- JSON array
    BusinessArea VARCHAR(100),
    CreatedAt DATETIME2 DEFAULT GETUTCDATE(),
    UNIQUE(CiaId, ItemId)
);

-- Assignees for impacted items
CREATE TABLE dbo.ItemAssignees (
    AssigneeId BIGINT PRIMARY KEY IDENTITY(1,1),
    ImpactedItemId BIGINT NOT NULL FOREIGN KEY REFERENCES dbo.ImpactedItems(ImpactedItemId),
    UserEmail VARCHAR(255) NOT NULL,
    UserObjectId VARCHAR(255), -- Azure AD Object ID
    DisplayName VARCHAR(255),
    Department VARCHAR(100),
    NotificationSent BIT DEFAULT 0,
    NotificationSentAt DATETIME2,
    NotificationMethod VARCHAR(50) DEFAULT 'Teams', -- Teams, Email, etc.
    CreatedAt DATETIME2 DEFAULT GETUTCDATE(),
    UNIQUE(ImpactedItemId, UserEmail)
);

-- Workflow execution runs
CREATE TABLE dbo.WorkflowRuns (
    WorkflowRunId BIGINT PRIMARY KEY IDENTITY(1,1),
    WorkflowName VARCHAR(100) NOT NULL,
    RunStatus VARCHAR(50) NOT NULL CHECK (RunStatus IN ('Started', 'InProgress', 'Completed', 'Failed')),
    SourcesQueried INT DEFAULT 0,
    ChangesDetected INT DEFAULT 0,
    CiasComputed INT DEFAULT 0,
    CiasComputedSuccessfully INT DEFAULT 0,
    CiasComputedFailed INT DEFAULT 0,
    NotificationsSent INT DEFAULT 0,
    ExecutionTimeSeconds INT,
    ErrorMessage NVARCHAR(MAX),
    StartedAt DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    CompletedAt DATETIME2,
    LastSuccessfulRunAt DATETIME2
);

-- Audit log for all operations
CREATE TABLE dbo.AuditLog (
    AuditLogId BIGINT PRIMARY KEY IDENTITY(1,1),
    Operation VARCHAR(50) NOT NULL, -- Create, Update, Delete, Query
    EntityType VARCHAR(50) NOT NULL, -- Change, CIA, ImpactedItem, etc.
    EntityId VARCHAR(255),
    UserId VARCHAR(255),
    ServiceName VARCHAR(100),
    OldValue NVARCHAR(MAX),
    NewValue NVARCHAR(MAX),
    IpAddress VARCHAR(50),
    CreatedAt DATETIME2 NOT NULL DEFAULT GETUTCDATE()
);

-- Dead-letter queue for failed items
CREATE TABLE dbo.DeadLetterQueue (
    QueueItemId BIGINT PRIMARY KEY IDENTITY(1,1),
    ChangeId VARCHAR(100),
    CiaId VARCHAR(100),
    ProcessType VARCHAR(50), -- 'ComputeCia', 'Persist', 'Notify'
    PayloadJson NVARCHAR(MAX),
    ErrorMessage NVARCHAR(MAX),
    RetryCount INT DEFAULT 0,
    MaxRetries INT DEFAULT 3,
    CreatedAt DATETIME2 DEFAULT GETUTCDATE(),
    LastRetryAt DATETIME2,
    ResolvedAt DATETIME2
);

-- Run tracking for idempotency
CREATE TABLE dbo.RunTracking (
    RunTrackingId INT PRIMARY KEY IDENTITY(1,1),
    RunId VARCHAR(100) NOT NULL UNIQUE,
    RunType VARCHAR(50), -- 'Daily', 'OnDemand', 'Retry'
    SourceSystemId INT FOREIGN KEY REFERENCES dbo.SourceSystems(SourceSystemId),
    LastSyncTimestamp DATETIME2,
    SyncCompletedAt DATETIME2,
    ItemsProcessed INT,
    CreatedAt DATETIME2 DEFAULT GETUTCDATE()
);

-- ============================================================================
-- INDEXES
-- ============================================================================

CREATE NONCLUSTERED INDEX IX_Changes_SourceSystemId ON dbo.Changes(SourceSystemId);
CREATE NONCLUSTERED INDEX IX_Changes_IsProcessed ON dbo.Changes(IsProcessed);
CREATE NONCLUSTERED INDEX IX_Changes_DetectedAt ON dbo.Changes(DetectedAt);

CREATE NONCLUSTERED INDEX IX_CIA_ChangeId ON dbo.ChangeImpactAnalysis(ChangeId);
CREATE NONCLUSTERED INDEX IX_CIA_ComputedAt ON dbo.ChangeImpactAnalysis(ComputedAt);

CREATE NONCLUSTERED INDEX IX_ImpactedItems_CiaId ON dbo.ImpactedItems(CiaId);
CREATE NONCLUSTERED INDEX IX_ImpactedItems_ItemId ON dbo.ImpactedItems(ItemId);
CREATE NONCLUSTERED INDEX IX_ImpactedItems_ImpactLevel ON dbo.ImpactedItems(ImpactLevel);

CREATE NONCLUSTERED INDEX IX_ItemAssignees_ImpactedItemId ON dbo.ItemAssignees(ImpactedItemId);
CREATE NONCLUSTERED INDEX IX_ItemAssignees_UserEmail ON dbo.ItemAssignees(UserEmail);
CREATE NONCLUSTERED INDEX IX_ItemAssignees_NotificationSent ON dbo.ItemAssignees(NotificationSent);

CREATE NONCLUSTERED INDEX IX_AuditLog_CreatedAt ON dbo.AuditLog(CreatedAt);
CREATE NONCLUSTERED INDEX IX_AuditLog_EntityType ON dbo.AuditLog(EntityType, EntityId);

CREATE NONCLUSTERED INDEX IX_DeadLetterQueue_CreatedAt ON dbo.DeadLetterQueue(CreatedAt);
CREATE NONCLUSTERED INDEX IX_DeadLetterQueue_RetryCount ON dbo.DeadLetterQueue(RetryCount);

CREATE NONCLUSTERED INDEX IX_RunTracking_RunId ON dbo.RunTracking(RunId);
CREATE NONCLUSTERED INDEX IX_RunTracking_SourceSystemId ON dbo.RunTracking(SourceSystemId);

-- ============================================================================
-- VIEWS
-- ============================================================================

CREATE VIEW dbo.vw_UnnotifiedAssignees AS
SELECT DISTINCT
    ia.UserEmail,
    ia.UserObjectId,
    ia.DisplayName,
    COUNT(DISTINCT ii.ImpactedItemId) as ImpactedItemCount,
    SUM(CASE WHEN ii.ImpactLevel = 'high' THEN 1 ELSE 0 END) as HighImpactCount,
    SUM(CASE WHEN ii.ImpactLevel = 'medium' THEN 1 ELSE 0 END) as MediumImpactCount,
    MIN(ii.CreatedAt) as OldestImpactDate
FROM dbo.ItemAssignees ia
JOIN dbo.ImpactedItems ii ON ia.ImpactedItemId = ii.ImpactedItemId
WHERE ia.NotificationSent = 0
GROUP BY ia.UserEmail, ia.UserObjectId, ia.DisplayName;

-- ============================================================================
-- STORED PROCEDURES
-- ============================================================================

CREATE PROCEDURE dbo.sp_LogAuditEvent
    @Operation VARCHAR(50),
    @EntityType VARCHAR(50),
    @EntityId VARCHAR(255),
    @UserId VARCHAR(255),
    @ServiceName VARCHAR(100),
    @NewValue NVARCHAR(MAX) = NULL,
    @OldValue NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    INSERT INTO dbo.AuditLog
        (Operation, EntityType, EntityId, UserId, ServiceName, NewValue, OldValue)
    VALUES
        (@Operation, @EntityType, @EntityId, @UserId, @ServiceName, @NewValue, @OldValue);
END;

CREATE PROCEDURE dbo.sp_GetUserImpactedItems
    @UserEmail VARCHAR(255),
    @Skip INT = 0,
    @Take INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT
        cia.CiaId,
        ii.ImpactedItemId,
        ii.ItemId,
        ii.ItemType,
        ii.ImpactLevel,
        ii.ImpactDescription,
        ii.AffectedSystems,
        ii.BusinessArea,
        ii.CreatedAt as ImpactDate,
        c.ChangeId,
        ss.SystemName as SourceSystem,
        c.ChangeType
    FROM dbo.ItemAssignees ia
    JOIN dbo.ImpactedItems ii ON ia.ImpactedItemId = ii.ImpactedItemId
    JOIN dbo.ChangeImpactAnalysis cia ON ii.CiaId = cia.CiaId
    JOIN dbo.Changes c ON cia.ChangeId = c.ChangeId
    JOIN dbo.SourceSystems ss ON c.SourceSystemId = ss.SourceSystemId
    WHERE ia.UserEmail = @UserEmail
    ORDER BY ii.CreatedAt DESC, ii.ImpactLevel DESC
    OFFSET @Skip ROWS
    FETCH NEXT @Take ROWS ONLY;
END;

-- ============================================================================
-- SAMPLE DATA
-- ============================================================================

INSERT INTO dbo.SourceSystems (SystemName, SystemCode, Description) VALUES
    ('SAP ERP', 'SAP', 'Enterprise Resource Planning'),
    ('Salesforce CRM', 'SFDC', 'Customer Relationship Management'),
    ('SQL Server Legacy', 'SQLLEGACY', 'Legacy SQL Server system'),
    ('REST API Service', 'RESTAPI', 'Third-party REST API'),
    ('PowerApps', 'PA', 'Microsoft Power Apps data');