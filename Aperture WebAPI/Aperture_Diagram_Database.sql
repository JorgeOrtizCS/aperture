/*
ApertureDB - complete SQL Server schema and camera-policy migration.

Run this ENTIRE file in SQL Server Management Studio, Azure Data Studio, or sqlcmd:
    sqlcmd -S YOUR_SERVER -E -d master -b -i Aperture_Diagram_Database.sql
Use your server's authentication method; no credentials or file paths are embedded.
Requires a SQL Server/Express instance and permission to create the database (if
absent) and alter its schema. SQL Server chooses its configured data/log locations.
This is T-SQL, not a MySQL, PostgreSQL, or SQLite script.

Creates all eight tables, relationships, defaults, constraints and indexes.
Safe to rerun on this schema; upgrades the earlier SQL Server diagram schema with
camera policy columns while preserving existing records. Does not drop or reset
anything, seed accounts, or import incompatible legacy/MySQL schemas. Unsupported
existing tables are reported rather than silently renamed or rewritten.

Default database name: ApertureDB. To use another name, replace EVERY occurrence
of ApertureDB in this file before execution and update the API connection string.
Times are UTC. MaximumViews is BIT: 1 = one view; 0 = unlimited.
Existing content gets camera protection OFF; senders select it for new items.

SQL stores metadata only. Moving an existing installation also requires a SQL
backup/data transfer and App_Data/ContentFiles from the WebAPI installation.
Bearer tokens and session device/IP bindings live in API memory, not SQL tables.
*/
USE [master];
GO
IF DB_ID(N'ApertureDB') IS NULL
    EXEC(N'CREATE DATABASE [ApertureDB];');
GO
USE [ApertureDB];
-- Keep this USE and the schema migration in the same batch.
IF DB_NAME() <> N'ApertureDB'
    THROW 50001, 'Database context is incorrect; no schema changes were made.', 1;
SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;
    IF OBJECT_ID(N'dbo.Users', N'U') IS NULL
    BEGIN
CREATE TABLE dbo.Users (
    UserID INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Users PRIMARY KEY,
    FirstName VARCHAR(100) NOT NULL,
    LastName VARCHAR(100) NOT NULL,
    Username VARCHAR(100) NOT NULL,
    PasswordHash VARCHAR(255) NOT NULL,
    DateCreated DATETIME NOT NULL CONSTRAINT DF_Users_DateCreated DEFAULT (GETUTCDATE()),
    CONSTRAINT UQ_Users_Username UNIQUE (Username)
);
    END;

    IF OBJECT_ID(N'dbo.Content', N'U') IS NULL
    BEGIN
CREATE TABLE dbo.Content (
    ContentID INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Content PRIMARY KEY,
    SenderID INT NOT NULL,
    FileType VARCHAR(50) NOT NULL,
    FileName VARCHAR(200) NOT NULL,
    UploadDate DATETIME NOT NULL CONSTRAINT DF_Content_UploadDate DEFAULT (GETUTCDATE()),
    CONSTRAINT FK_Content_Users FOREIGN KEY (SenderID) REFERENCES dbo.Users(UserID)
);
    END;

    IF OBJECT_ID(N'dbo.ContentRecipient', N'U') IS NULL
    BEGIN
CREATE TABLE dbo.ContentRecipient (
    RecipientID INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ContentRecipient PRIMARY KEY,
    UserID INT NOT NULL,
    ContentID INT NOT NULL,
    AccessStatus VARCHAR(20) NOT NULL CONSTRAINT DF_ContentRecipient_AccessStatus DEFAULT ('Active'),
    DateShared DATETIME NOT NULL CONSTRAINT DF_ContentRecipient_DateShared DEFAULT (GETUTCDATE()),
    CONSTRAINT FK_ContentRecipient_Users FOREIGN KEY (UserID) REFERENCES dbo.Users(UserID),
    CONSTRAINT FK_ContentRecipient_Content FOREIGN KEY (ContentID) REFERENCES dbo.Content(ContentID),
    CONSTRAINT UQ_ContentRecipient_Recipient_Content UNIQUE (RecipientID, ContentID),
    CONSTRAINT CK_ContentRecipient_AccessStatus CHECK (AccessStatus IN ('Active','Pending','Revoked'))
);
    END;

    IF OBJECT_ID(N'dbo.TrustedDevices', N'U') IS NULL
    BEGIN
CREATE TABLE dbo.TrustedDevices (
    DeviceID INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_TrustedDevices PRIMARY KEY,
    UserID INT NOT NULL,
    DeviceIdentifier VARCHAR(255) NOT NULL,
    IsTrusted BIT NOT NULL CONSTRAINT DF_TrustedDevices_IsTrusted DEFAULT (0),
    DateRegistered DATETIME NOT NULL CONSTRAINT DF_TrustedDevices_DateRegistered DEFAULT (GETUTCDATE()),
    DeviceType VARCHAR(50) NULL,
    DeviceName VARCHAR(100) NULL,
    CONSTRAINT FK_TrustedDevices_Users FOREIGN KEY (UserID) REFERENCES dbo.Users(UserID),
    CONSTRAINT UQ_TrustedDevices_User_Device UNIQUE (UserID,DeviceIdentifier)
);
    END;

    IF OBJECT_ID(N'dbo.AccessPolicy', N'U') IS NULL
    BEGIN
CREATE TABLE dbo.AccessPolicy (
    PolicyID INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_AccessPolicy PRIMARY KEY,
    ContentID INT NOT NULL,
    StartTime DATETIME NULL,
    ExpirationDate DATETIME NULL,
    RequiredLocation VARCHAR(255) NULL,
    TrustedDevice BIT NOT NULL CONSTRAINT DF_AccessPolicy_TrustedDevice DEFAULT (0),
    MaximumViews BIT NOT NULL CONSTRAINT DF_AccessPolicy_MaximumViews DEFAULT (0),
    ScreenshotRestriction BIT NOT NULL CONSTRAINT DF_AccessPolicy_ScreenshotRestriction DEFAULT (0),
    CameraDetectionEnabled BIT NOT NULL CONSTRAINT DF_AccessPolicy_CameraDetectionEnabled DEFAULT (0),
    BlockPhones BIT NOT NULL CONSTRAINT DF_AccessPolicy_BlockPhones DEFAULT (0),
    BlockMultiplePeople BIT NOT NULL CONSTRAINT DF_AccessPolicy_BlockMultiplePeople DEFAULT (0),
    RequireViewer BIT NOT NULL CONSTRAINT DF_AccessPolicy_RequireViewer DEFAULT (0),
    PolicyStatus VARCHAR(30) NOT NULL CONSTRAINT DF_AccessPolicy_PolicyStatus DEFAULT ('Active'),
    DateCreated DATETIME NOT NULL CONSTRAINT DF_AccessPolicy_DateCreated DEFAULT (GETUTCDATE()),
    CONSTRAINT FK_AccessPolicy_Content FOREIGN KEY (ContentID) REFERENCES dbo.Content(ContentID),
    CONSTRAINT UQ_AccessPolicy_ContentID UNIQUE (ContentID),
    CONSTRAINT CK_AccessPolicy_Dates CHECK (StartTime IS NULL OR ExpirationDate IS NULL OR ExpirationDate > StartTime),
    CONSTRAINT CK_AccessPolicy_Status CHECK (PolicyStatus IN ('Active','Paused','Revoked'))
);
    END;

    IF OBJECT_ID(N'dbo.ViewingSession', N'U') IS NULL
    BEGIN
CREATE TABLE dbo.ViewingSession (
    SessionID INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ViewingSession PRIMARY KEY,
    RecipientID INT NOT NULL,
    ContentID INT NOT NULL,
    SessionStart DATETIME NOT NULL CONSTRAINT DF_ViewingSession_SessionStart DEFAULT (GETUTCDATE()),
    SessionEnd DATETIME NULL,
    SessionStatus VARCHAR(30) NOT NULL CONSTRAINT DF_ViewingSession_SessionStatus DEFAULT ('Active'),
    CONSTRAINT FK_ViewingSession_Recipient_Content FOREIGN KEY (RecipientID,ContentID)
        REFERENCES dbo.ContentRecipient(RecipientID,ContentID),
    CONSTRAINT FK_ViewingSession_Content FOREIGN KEY (ContentID) REFERENCES dbo.Content(ContentID),
    CONSTRAINT CK_ViewingSession_Dates CHECK (SessionEnd IS NULL OR SessionEnd >= SessionStart),
    CONSTRAINT CK_ViewingSession_Status CHECK (SessionStatus IN ('Active','Ended','Revoked','Expired'))
);
    END;

    IF OBJECT_ID(N'dbo.EnvironmentCheck', N'U') IS NULL
    BEGIN
CREATE TABLE dbo.EnvironmentCheck (
    CheckID INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_EnvironmentCheck PRIMARY KEY,
    SessionID INT NOT NULL,
    CheckTime DATETIME NOT NULL CONSTRAINT DF_EnvironmentCheck_CheckTime DEFAULT (GETUTCDATE()),
    ViewCount INT NOT NULL CONSTRAINT DF_EnvironmentCheck_ViewCount DEFAULT (0),
    LocationVerified BIT NOT NULL,
    DeviceVerified BIT NOT NULL,
    PolicySatisfied BIT NOT NULL,
    ViolationType VARCHAR(100) NULL,
    CONSTRAINT FK_EnvironmentCheck_Session FOREIGN KEY (SessionID) REFERENCES dbo.ViewingSession(SessionID),
    CONSTRAINT CK_EnvironmentCheck_ViewCount CHECK (ViewCount >= 0)
);
    END;

    IF OBJECT_ID(N'dbo.AuditLogs', N'U') IS NULL
    BEGIN
CREATE TABLE dbo.AuditLogs (
    LogID INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_AuditLogs PRIMARY KEY,
    UserID INT NULL,
    EventType VARCHAR(50) NOT NULL,
    Description VARCHAR(MAX) NULL,
    EventTime DATETIME NOT NULL CONSTRAINT DF_AuditLogs_EventTime DEFAULT (GETUTCDATE()),
    CONSTRAINT FK_AuditLogs_Users FOREIGN KEY (UserID) REFERENCES dbo.Users(UserID)
);
    END;

    -- Upgrade existing SQL Server installations without changing existing policies.
    IF COL_LENGTH(N'dbo.AccessPolicy', N'CameraDetectionEnabled') IS NULL
        ALTER TABLE dbo.AccessPolicy ADD CameraDetectionEnabled BIT NOT NULL
            CONSTRAINT DF_AccessPolicy_CameraDetectionEnabled DEFAULT (0) WITH VALUES;
    IF COL_LENGTH(N'dbo.AccessPolicy', N'BlockPhones') IS NULL
        ALTER TABLE dbo.AccessPolicy ADD BlockPhones BIT NOT NULL
            CONSTRAINT DF_AccessPolicy_BlockPhones DEFAULT (0) WITH VALUES;
    IF COL_LENGTH(N'dbo.AccessPolicy', N'BlockMultiplePeople') IS NULL
        ALTER TABLE dbo.AccessPolicy ADD BlockMultiplePeople BIT NOT NULL
            CONSTRAINT DF_AccessPolicy_BlockMultiplePeople DEFAULT (0) WITH VALUES;
    IF COL_LENGTH(N'dbo.AccessPolicy', N'RequireViewer') IS NULL
        ALTER TABLE dbo.AccessPolicy ADD RequireViewer BIT NOT NULL
            CONSTRAINT DF_AccessPolicy_RequireViewer DEFAULT (0) WITH VALUES;

    -- Do not report success on a different, incompatible legacy schema.
    DECLARE @ExpectedColumns TABLE (TableName SYSNAME, ColumnName SYSNAME);
    INSERT INTO @ExpectedColumns(TableName, ColumnName) VALUES
        (N'Users', N'UserID'),
        (N'Users', N'FirstName'),
        (N'Users', N'LastName'),
        (N'Users', N'Username'),
        (N'Users', N'PasswordHash'),
        (N'Users', N'DateCreated'),
        (N'Content', N'ContentID'),
        (N'Content', N'SenderID'),
        (N'Content', N'FileType'),
        (N'Content', N'FileName'),
        (N'Content', N'UploadDate'),
        (N'ContentRecipient', N'RecipientID'),
        (N'ContentRecipient', N'UserID'),
        (N'ContentRecipient', N'ContentID'),
        (N'ContentRecipient', N'AccessStatus'),
        (N'ContentRecipient', N'DateShared'),
        (N'TrustedDevices', N'DeviceID'),
        (N'TrustedDevices', N'UserID'),
        (N'TrustedDevices', N'DeviceIdentifier'),
        (N'TrustedDevices', N'IsTrusted'),
        (N'TrustedDevices', N'DateRegistered'),
        (N'TrustedDevices', N'DeviceType'),
        (N'TrustedDevices', N'DeviceName'),
        (N'AccessPolicy', N'PolicyID'),
        (N'AccessPolicy', N'ContentID'),
        (N'AccessPolicy', N'StartTime'),
        (N'AccessPolicy', N'ExpirationDate'),
        (N'AccessPolicy', N'RequiredLocation'),
        (N'AccessPolicy', N'TrustedDevice'),
        (N'AccessPolicy', N'MaximumViews'),
        (N'AccessPolicy', N'ScreenshotRestriction'),
        (N'AccessPolicy', N'CameraDetectionEnabled'),
        (N'AccessPolicy', N'BlockPhones'),
        (N'AccessPolicy', N'BlockMultiplePeople'),
        (N'AccessPolicy', N'RequireViewer'),
        (N'AccessPolicy', N'PolicyStatus'),
        (N'AccessPolicy', N'DateCreated'),
        (N'ViewingSession', N'SessionID'),
        (N'ViewingSession', N'RecipientID'),
        (N'ViewingSession', N'ContentID'),
        (N'ViewingSession', N'SessionStart'),
        (N'ViewingSession', N'SessionEnd'),
        (N'ViewingSession', N'SessionStatus'),
        (N'EnvironmentCheck', N'CheckID'),
        (N'EnvironmentCheck', N'SessionID'),
        (N'EnvironmentCheck', N'CheckTime'),
        (N'EnvironmentCheck', N'ViewCount'),
        (N'EnvironmentCheck', N'LocationVerified'),
        (N'EnvironmentCheck', N'DeviceVerified'),
        (N'EnvironmentCheck', N'PolicySatisfied'),
        (N'EnvironmentCheck', N'ViolationType'),
        (N'AuditLogs', N'LogID'),
        (N'AuditLogs', N'UserID'),
        (N'AuditLogs', N'EventType'),
        (N'AuditLogs', N'Description'),
        (N'AuditLogs', N'EventTime');
    IF EXISTS (
        SELECT 1 FROM @ExpectedColumns e
        WHERE NOT EXISTS (
            SELECT 1 FROM sys.columns c
            WHERE c.object_id = OBJECT_ID(N'dbo.' + e.TableName, N'U')
              AND c.name = e.ColumnName
        )
    )
    BEGIN
        SELECT e.TableName AS IncompatibleTable, e.ColumnName AS MissingColumn
        FROM @ExpectedColumns e
        WHERE NOT EXISTS (
            SELECT 1 FROM sys.columns c
            WHERE c.object_id = OBJECT_ID(N'dbo.' + e.TableName, N'U')
              AND c.name = e.ColumnName
        );
        THROW 50002, 'Existing tables do not match the supported Aperture SQL Server schema. Migration rolled back.', 1;
    END;

    -- Restore missing secondary indexes without recreating or duplicating them.
    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.Content') AND name = N'IX_Content_SenderID')
        CREATE INDEX IX_Content_SenderID ON dbo.Content(SenderID);
    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.ContentRecipient') AND name = N'UX_ContentRecipient_User_Content')
        CREATE UNIQUE INDEX UX_ContentRecipient_User_Content
 ON dbo.ContentRecipient(UserID,ContentID);
    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.ContentRecipient') AND name = N'IX_ContentRecipient_ContentID')
        CREATE INDEX IX_ContentRecipient_ContentID ON dbo.ContentRecipient(ContentID);
    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.ViewingSession') AND name = N'IX_ViewingSession_RecipientID')
        CREATE INDEX IX_ViewingSession_RecipientID ON dbo.ViewingSession(RecipientID,SessionStart DESC);
    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.EnvironmentCheck') AND name = N'IX_EnvironmentCheck_SessionID_CheckTime')
        CREATE INDEX IX_EnvironmentCheck_SessionID_CheckTime
 ON dbo.EnvironmentCheck(SessionID,CheckTime DESC);
    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.AuditLogs') AND name = N'IX_AuditLogs_UserID_EventTime')
        CREATE INDEX IX_AuditLogs_UserID_EventTime ON dbo.AuditLogs(UserID,EventTime DESC);
    COMMIT TRANSACTION;
    PRINT 'ApertureDB ready: all 8 tables and camera policy fields are installed.';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;