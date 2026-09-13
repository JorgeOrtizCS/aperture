/* Aperture database — matches the supplied ER diagram.
   Target: Microsoft SQL Server / SQL Server Express (SSMS).
   Run as a login allowed to create databases and tables.
   Intended for a NEW database: this script stops if any expected table exists.
   Times are stored in UTC by the defaults; applications must write UTC too.
*/
IF DB_ID(N'ApertureDB') IS NULL
    CREATE DATABASE ApertureDB;
GO
USE ApertureDB;
GO
SET XACT_ABORT ON;
IF OBJECT_ID(N'dbo.Users',N'U') IS NOT NULL
 OR OBJECT_ID(N'dbo.Content',N'U') IS NOT NULL
 OR OBJECT_ID(N'dbo.ContentRecipient',N'U') IS NOT NULL
 OR OBJECT_ID(N'dbo.ViewingSession',N'U') IS NOT NULL
 OR OBJECT_ID(N'dbo.EnvironmentCheck',N'U') IS NOT NULL
 OR OBJECT_ID(N'dbo.TrustedDevices',N'U') IS NOT NULL
 OR OBJECT_ID(N'dbo.AccessPolicy',N'U') IS NOT NULL
 OR OBJECT_ID(N'dbo.AuditLogs',N'U') IS NOT NULL
BEGIN
    THROW 50001, 'Aperture schema tables already exist. Use a migration instead of rerunning the create script.', 1;
END;

BEGIN TRANSACTION;

CREATE TABLE dbo.Users (
    UserID INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Users PRIMARY KEY,
    FirstName VARCHAR(100) NOT NULL,
    LastName VARCHAR(100) NOT NULL,
    Username VARCHAR(100) NOT NULL,
    PasswordHash VARCHAR(255) NOT NULL,
    DateCreated DATETIME NOT NULL CONSTRAINT DF_Users_DateCreated DEFAULT (GETUTCDATE()),
    CONSTRAINT UQ_Users_Username UNIQUE (Username)
);

CREATE TABLE dbo.Content (
    ContentID INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Content PRIMARY KEY,
    SenderID INT NOT NULL,
    FileType VARCHAR(50) NOT NULL,
    FileName VARCHAR(200) NOT NULL,
    UploadDate DATETIME NOT NULL CONSTRAINT DF_Content_UploadDate DEFAULT (GETUTCDATE()),
    CONSTRAINT FK_Content_Users FOREIGN KEY (SenderID) REFERENCES dbo.Users(UserID)
);
CREATE INDEX IX_Content_SenderID ON dbo.Content(SenderID);

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
-- Prevent sharing the same content with the same user twice. The diagram's
-- (RecipientID,ContentID) unique rule is also present above as written.
CREATE UNIQUE INDEX UX_ContentRecipient_User_Content
 ON dbo.ContentRecipient(UserID,ContentID);
CREATE INDEX IX_ContentRecipient_ContentID ON dbo.ContentRecipient(ContentID);

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

CREATE TABLE dbo.AccessPolicy (
    PolicyID INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_AccessPolicy PRIMARY KEY,
    ContentID INT NOT NULL,
    StartTime DATETIME NULL,
    ExpirationDate DATETIME NULL,
    RequiredLocation VARCHAR(255) NULL,
    TrustedDevice BIT NOT NULL CONSTRAINT DF_AccessPolicy_TrustedDevice DEFAULT (0),
    MaximumViews BIT NOT NULL CONSTRAINT DF_AccessPolicy_MaximumViews DEFAULT (0),
    ScreenshotRestriction BIT NOT NULL CONSTRAINT DF_AccessPolicy_ScreenshotRestriction DEFAULT (0),
    PolicyStatus VARCHAR(30) NOT NULL CONSTRAINT DF_AccessPolicy_PolicyStatus DEFAULT ('Active'),
    DateCreated DATETIME NOT NULL CONSTRAINT DF_AccessPolicy_DateCreated DEFAULT (GETUTCDATE()),
    CONSTRAINT FK_AccessPolicy_Content FOREIGN KEY (ContentID) REFERENCES dbo.Content(ContentID),
    CONSTRAINT UQ_AccessPolicy_ContentID UNIQUE (ContentID),
    CONSTRAINT CK_AccessPolicy_Dates CHECK (StartTime IS NULL OR ExpirationDate IS NULL OR ExpirationDate > StartTime),
    CONSTRAINT CK_AccessPolicy_Status CHECK (PolicyStatus IN ('Active','Paused','Revoked'))
);

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
CREATE INDEX IX_ViewingSession_RecipientID ON dbo.ViewingSession(RecipientID,SessionStart DESC);

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
CREATE INDEX IX_EnvironmentCheck_SessionID_CheckTime
 ON dbo.EnvironmentCheck(SessionID,CheckTime DESC);

CREATE TABLE dbo.AuditLogs (
    LogID INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_AuditLogs PRIMARY KEY,
    UserID INT NULL,
    EventType VARCHAR(50) NOT NULL,
    Description VARCHAR(MAX) NULL,
    EventTime DATETIME NOT NULL CONSTRAINT DF_AuditLogs_EventTime DEFAULT (GETUTCDATE()),
    CONSTRAINT FK_AuditLogs_Users FOREIGN KEY (UserID) REFERENCES dbo.Users(UserID)
);
CREATE INDEX IX_AuditLogs_UserID_EventTime ON dbo.AuditLogs(UserID,EventTime DESC);

COMMIT TRANSACTION;
PRINT 'ApertureDB created: 8 tables, foreign keys, constraints, and indexes.';
