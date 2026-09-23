CREATE DATABASE IF NOT EXISTS APERTURE_DB;
USE APERTURE_DB; 

CREATE TABLE Users (
    UserID INT auto_increment primary key,
    First_Name varchar(100) not null, 
    Last_Name varchar(100) not null, 
    username varchar(100) not null unique, 
    PasswordHash varchar(255) not null, 
    Date_created datetime default current_timestamp 
    );

CREATE TABLE Content(
    ContentID int auto_increment primary key NOT NULL,
    SenderID int NOT NULL, 
    File_Type varchar(200),
    File_Name varchar(200),
    Upload_Date datetime,
    FOREIGN KEY (SenderID) REFERENCES Users(UserID)
);
CREATE TABLE ContentRecipient(
    RecipientID INT auto_increment PRIMARY KEY NOT NULL, 
    Access_Status VARCHAR (100),
    Date_Shared DATETIME, 
    UserID INT, 
    ContentID INT, 
    UNIQUE (UserID, ContentID),
    FOREIGN KEY (UserID) REFERENCES Users(UserID),
    FOREIGN KEY (ContentID) REFERENCES Content(ContentID)
); 
CREATE TABLE ViewingSession(
    SessionID INT auto_increment PRIMARY KEY NOT NULL,
    RecipientID int,
    Session_Start datetime, 
    Session_End datetime,
    Session_Status varchar(100),
    FOREIGN KEY (RecipientID) REFERENCES ContentRecipient(RecipientID)
);

CREATE TABLE AuditLogs(
    LogID INT auto_increment PRIMARY KEY NOT NULL,
    UserID INT,
    Description_ text, 
    EventTime DATETIME,
    EventType VARCHAR(100),
    FOREIGN KEY (UserID) REFERENCES Users(UserID)
); 

CREATE TABLE EnvironmentCheck(
    CheckID INT auto_increment PRIMARY KEY NOT NULL,
    SessionID INT, 
    Check_Timestamp DATETIME,
    ViewCount INT, 
    LocationVerified BOOLEAN,
    DeviceVerified BOOLEAN,
    PolicySatisfied BOOLEAN,
    ViolationType VARCHAR(100),
    FOREIGN KEY (SessionID) REFERENCES ViewingSession(SessionID)
);

CREATE Table TrustedDevices(
    DeviceID INT auto_increment PRIMARY KEY NOT NULL,
    UserID INT, 
    IsTrusted BOOLEAN,
    DateRegistered DATETIME,
    DeviceName VARCHAR(100),
    DeviceType VARCHAR(100),
    FOREIGN KEY (UserID) REFERENCES Users(UserID) 
);

Create TABLE AccessPolicy(
    PolicyID INT auto_increment PRIMARY KEY NOT NULL,
    ContentID INT,
    StartTime DATETIME,
    ExpirationDate DATETIME,
    MaximumViewers INT,
    RequiredLocation VARCHAR(250),
    ScreenShot_Restriction BOOLEAN,
    TrustedDevice BOOLEAN,
    PolicyStatus VARCHAR(100),
    DateCreated DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (ContentID) REFERENCES Content(ContentID)
);
