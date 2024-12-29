-- Create the database
CREATE DATABASE CarpoolingSystem2;
GO

-- Use the created database
USE CarpoolingSystem2;
GO

-- USERS TABLE
CREATE TABLE Users (
    UserID INT IDENTITY(1,1) PRIMARY KEY, -- Unique identifier for each user
    FullName VARCHAR(100) NOT NULL,       -- User's full name
    Email VARCHAR(100) NOT NULL UNIQUE,  -- Email must be unique
    PhoneNumber VARCHAR(15) NOT NULL UNIQUE, -- Phone number must be unique
    PasswordHash VARCHAR(255) NOT NULL,  -- Encrypted password
    Role VARCHAR(20) DEFAULT 'Rider' CHECK (Role IN ('Rider', 'Driver', 'Admin')), -- User roles
    CreatedDate DATETIME DEFAULT GETDATE(), -- Timestamp for record creation
    UpdatedDate DATETIME DEFAULT GETDATE(), -- Timestamp for last update
    IsActive BIT DEFAULT 1 -- Soft delete flag (1 = active, 0 = deactivated)
);

-- RIDES TABLE
CREATE TABLE Rides (
    RideID INT IDENTITY(1,1) PRIMARY KEY, -- Unique identifier for each ride
    DriverID INT NOT NULL,               -- Foreign key referencing Users table
    StartLocation VARCHAR(255) NOT NULL, -- Starting point of the ride
    Destination VARCHAR(255) NOT NULL,  -- Ending point of the ride
    RideDate DATE NOT NULL,              -- Date of the ride
    RideTime TIME NOT NULL,              -- Time of the ride
    AvailableSeats INT NOT NULL CHECK (AvailableSeats BETWEEN 1 AND 10), -- Number of seats available
    CostPerSeat DECIMAL(10, 2) NOT NULL DEFAULT 0.00, -- Cost per seat
    Comments VARCHAR(255) NULL,         -- Optional comments for the ride
    RideStatus VARCHAR(50) DEFAULT 'Scheduled', -- Status of the ride
    CreatedDate DATETIME DEFAULT GETDATE(), -- Timestamp for record creation
    UpdatedDate DATETIME DEFAULT GETDATE(), -- Timestamp for last update
    FOREIGN KEY (DriverID) REFERENCES Users(UserID), -- Linking to Users table
    RideCode AS CONCAT('RIDE-', RideID) PERSISTED -- Computed column for unique ride code
);

CREATE TABLE Bookings (
    BookingID INT IDENTITY(1,1) PRIMARY KEY, 
    RideID INT NOT NULL,
    PassengerID INT NOT NULL,
    BookingDate DATETIME DEFAULT GETDATE(),
    SeatsBooked INT NOT NULL CHECK (SeatsBooked > 0),
    TotalCost DECIMAL(10, 2) NOT NULL, -- Regular column
    FOREIGN KEY (RideID) REFERENCES Rides(RideID),
    FOREIGN KEY (PassengerID) REFERENCES Users(UserID)
);

-- AUDIT LOGS TABLE
CREATE TABLE AuditLogs (
    LogID INT IDENTITY(1,1) PRIMARY KEY, -- Unique identifier for each log
    UserID INT NULL,                     -- Foreign key referencing Users table
    OperationType VARCHAR(50),          -- Type of operation (e.g., AddRide, BookRide)
    OperationDetails VARCHAR(255),      -- Description of the operation
    OperationDate DATETIME DEFAULT GETDATE(), -- Timestamp for the operation
    FOREIGN KEY (UserID) REFERENCES Users(UserID) -- Linking to Users table
);

-- FEEDBACK TABLE
CREATE TABLE Feedback (
    FeedbackID INT IDENTITY(1,1) PRIMARY KEY, -- Unique identifier for each feedback
    RideID INT NOT NULL,                     -- Foreign key referencing Rides table
    UserID INT NOT NULL,                     -- Foreign key referencing Users table
    Rating INT NOT NULL CHECK (Rating BETWEEN 1 AND 5), -- Rating between 1 and 5
    Comment VARCHAR(255),                   -- Optional comment
    CreatedDate DATETIME DEFAULT GETDATE(), -- Timestamp for record creation
    FOREIGN KEY (RideID) REFERENCES Rides(RideID), -- Linking to Rides table
    FOREIGN KEY (UserID) REFERENCES Users(UserID) -- Linking to Users table
);

-- NOTIFICATIONS TABLE
CREATE TABLE Notifications (
    NotificationID INT IDENTITY(1,1) PRIMARY KEY, -- Unique identifier for each notification
    UserID INT NOT NULL,                         -- Foreign key referencing Users table
    Message VARCHAR(255) NOT NULL,              -- Notification message
    NotificationDate DATETIME DEFAULT GETDATE(), -- Timestamp for notification creation
    IsRead BIT DEFAULT 0,                        -- Flag for read/unread status (0 = unread, 1 = read)
    NotificationType VARCHAR(50) NULL,          -- Type of notification (e.g., Reminder, Confirmation)
    FOREIGN KEY (UserID) REFERENCES Users(UserID) -- Linking to Users table
);

-- TRIGGERS

-- Trigger to log ride additions
CREATE TRIGGER trg_AddRideAudit
ON Rides
AFTER INSERT
AS
BEGIN
    INSERT INTO AuditLogs (UserID, OperationType, OperationDetails)
    SELECT 
        DriverID, 
        'AddRide', 
        CONCAT('Ride from ', StartLocation, ' to ', Destination, ' on ', RideDate, ' at ', RideTime)
    FROM inserted;
END;

-- Trigger to log booking additions
CREATE TRIGGER trg_BookRideAudit
ON Bookings
AFTER INSERT
AS
BEGIN
    INSERT INTO AuditLogs (UserID, OperationType, OperationDetails)
    SELECT 
        PassengerID, 
        'BookRide', 
        CONCAT('Booked ', SeatsBooked, ' seats on RideID: ', RideID)
    FROM inserted;
END;

-- Trigger to calculate TotalCost
CREATE TRIGGER trg_CalculateTotalCost
ON Bookings
AFTER INSERT
AS
BEGIN
    UPDATE b
    SET b.TotalCost = b.SeatsBooked * r.CostPerSeat
    FROM Bookings b
    INNER JOIN Rides r ON b.RideID = r.RideID
    WHERE b.BookingID IN (SELECT BookingID FROM inserted);
END;

-- STORED PROCEDURES

-- Procedure to add a new ride
CREATE PROCEDURE sp_AddRide
    @DriverID INT,
    @StartLocation VARCHAR(255),
    @Destination VARCHAR(255),
    @RideDate DATE,
    @RideTime TIME,
    @AvailableSeats INT,
    @CostPerSeat DECIMAL(10, 2),
    @Comments VARCHAR(255)
AS
BEGIN
    INSERT INTO Rides (DriverID, StartLocation, Destination, RideDate, RideTime, AvailableSeats, CostPerSeat, Comments)
    VALUES (@DriverID, @StartLocation, @Destination, @RideDate, @RideTime, @AvailableSeats, @CostPerSeat, @Comments);
END;

-- Procedure to search for rides
CREATE PROCEDURE sp_SearchRides
    @StartLocation VARCHAR(255) = NULL,
    @Destination VARCHAR(255) = NULL,
    @StartDate DATE = NULL,
    @EndDate DATE = NULL,
    @MinCost DECIMAL(10, 2) = NULL,
    @MaxCost DECIMAL(10, 2) = NULL
AS
BEGIN
    SELECT 
        RideID, 
        RideCode, 
        StartLocation, 
        Destination, 
        RideDate, 
        RideTime, 
        AvailableSeats, 
        CostPerSeat, 
        Comments
    FROM Rides
    WHERE 
        (@StartLocation IS NULL OR StartLocation = @StartLocation) AND
        (@Destination IS NULL OR Destination = @Destination) AND
        (@StartDate IS NULL OR RideDate >= @StartDate) AND
        (@EndDate IS NULL OR RideDate <= @EndDate) AND
        (@MinCost IS NULL OR CostPerSeat >= @MinCost) AND
        (@MaxCost IS NULL OR CostPerSeat <= @MaxCost)
        AND AvailableSeats > 0
        AND RideStatus = 'Scheduled';
END;

-- Procedure to book a ride
CREATE PROCEDURE sp_BookRide
    @RideID INT,
    @PassengerID INT,
    @SeatsBooked INT
AS
BEGIN
    BEGIN TRANSACTION;

    DECLARE @AvailableSeats INT;
    SELECT @AvailableSeats = AvailableSeats FROM Rides WHERE RideID = @RideID;

    IF @AvailableSeats >= @SeatsBooked
    BEGIN
        INSERT INTO Bookings (RideID, PassengerID, SeatsBooked)
        VALUES (@RideID, @PassengerID, @SeatsBooked);

        UPDATE Rides
        SET AvailableSeats = AvailableSeats - @SeatsBooked
        WHERE RideID = @RideID;
    END
    ELSE
    BEGIN
        ROLLBACK TRANSACTION;
        RAISERROR ('Not enough seats available.', 16, 1);
        RETURN;
    END;

    COMMIT TRANSACTION;
END;

-- Procedure to cancel a booking
CREATE PROCEDURE sp_CancelBooking
    @BookingID INT
AS
BEGIN
    BEGIN TRANSACTION;

    DECLARE @RideID INT, @SeatsBooked INT;

    SELECT @RideID = RideID, @SeatsBooked = SeatsBooked
    FROM Bookings WHERE BookingID = @BookingID;

    DELETE FROM Bookings WHERE BookingID = @BookingID;

    UPDATE Rides
    SET AvailableSeats = AvailableSeats + @SeatsBooked
    WHERE RideID = @RideID;

    COMMIT TRANSACTION;
END;

-- VIEWS

-- View for available rides
CREATE VIEW vw_AvailableRides AS
SELECT 
    RideID, RideCode, StartLocation, Destination, RideDate, RideTime, AvailableSeats, Comments
FROM Rides
WHERE AvailableSeats > 0 AND RideStatus = 'Scheduled';

-- View for user bookings
CREATE VIEW vw_UserBookings AS
SELECT 
    b.BookingID, 
    u.FullName AS Passenger, 
    b.PassengerID, 
    r.StartLocation, 
    r.Destination, 
    r.RideDate, 
    r.RideTime, 
    b.SeatsBooked
FROM Bookings b
JOIN Users u ON b.PassengerID = u.UserID
JOIN Rides r ON b.RideID = r.RideID;

-- View for driver feedback summary
CREATE VIEW vw_DriverFeedbackSummary AS
SELECT 
    r.DriverID,
    u.FullName AS DriverName,
    COUNT(f.FeedbackID) AS TotalFeedbacks,
    AVG(f.Rating) AS AverageRating
FROM Feedback f
JOIN Rides r ON f.RideID = r.RideID
JOIN Users u ON r.DriverID = u.UserID
GROUP BY r.DriverID, u.FullName;


CREATE TABLE Roles (
    RoleID INT IDENTITY(1,1) PRIMARY KEY,
    RoleName VARCHAR(50) NOT NULL UNIQUE
);

-- Populate default roles
INSERT INTO Roles (RoleName) VALUES ('Rider'), ('Driver'), ('Admin');

ALTER TABLE Users
DROP COLUMN Role; -- Remove the old Role column

ALTER TABLE Users
ADD RoleID INT NOT NULL DEFAULT 1, -- Default to 'Rider'
    FOREIGN KEY (RoleID) REFERENCES Roles(RoleID);

ALTER TABLE AuditLogs
ADD IPAddress VARCHAR(50) NULL, -- Tracks user's IP address during operations
    LoginSuccess BIT NULL;      -- Indicates whether the login was successful (1 = Yes, 0 = No)


CREATE PROCEDURE sp_LogLoginActivity
    @UserID INT,
    @OperationType VARCHAR(50),
    @IPAddress VARCHAR(50),
    @LoginSuccess BIT
AS
BEGIN
    INSERT INTO AuditLogs (UserID, OperationType, IPAddress, LoginSuccess, OperationDate)
    VALUES (@UserID, @OperationType, @IPAddress, @LoginSuccess, GETDATE());
END;


