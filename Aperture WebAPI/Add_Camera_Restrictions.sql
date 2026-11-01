-- Existing SQL Server databases. Safe to rerun; existing policies keep camera checks off.
USE ApertureDB;
GO
SET XACT_ABORT ON;
IF OBJECT_ID(N'dbo.AccessPolicy', N'U') IS NULL
    THROW 50001, 'AccessPolicy is missing. Run Aperture_Diagram_Database.sql for a new database.', 1;
BEGIN TRANSACTION;
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
COMMIT TRANSACTION;
PRINT 'Camera policy columns ready.';
