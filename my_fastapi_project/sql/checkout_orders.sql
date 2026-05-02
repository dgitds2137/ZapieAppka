IF OBJECT_ID(N'dbo.Users', N'U') IS NULL
BEGIN
    PRINT N'Pomijam checkout_orders.sql, bo tabela dbo.Users jeszcze nie istnieje.';
END;
GO

IF OBJECT_ID(N'dbo.Users', N'U') IS NOT NULL
   AND OBJECT_ID(N'dbo.CheckoutOrders', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.CheckoutOrders (
        checkout_order_id INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        verification_id NVARCHAR(32) NOT NULL,
        user_id INT NULL,
        assigned_to_user_id INT NULL,
        status NVARCHAR(50) NOT NULL,
        processing_status NVARCHAR(50) NOT NULL
            CONSTRAINT DF_CheckoutOrders_processing_status DEFAULT N'unassigned',
        verification_stage NVARCHAR(50) NOT NULL,
        payment_method NVARCHAR(50) NOT NULL,
        currency NVARCHAR(10) NOT NULL,
        subtotal_amount DECIMAL(10, 2) NOT NULL
            CONSTRAINT DF_CheckoutOrders_subtotal_amount DEFAULT (0),
        total_amount DECIMAL(10, 2) NOT NULL,
        redeemed_points INT NOT NULL
            CONSTRAINT DF_CheckoutOrders_redeemed_points DEFAULT (0),
        redeemed_amount DECIMAL(10, 2) NOT NULL
            CONSTRAINT DF_CheckoutOrders_redeemed_amount DEFAULT (0),
        eta_minutes INT NOT NULL,
        fulfillment_method NVARCHAR(80) NOT NULL,
        fulfillment_option_index INT NOT NULL,
        address_option_index INT NOT NULL,
        address_title NVARCHAR(200) NOT NULL,
        address_subtitle NVARCHAR(255) NOT NULL,
        address_eta_label NVARCHAR(50) NOT NULL,
        notes NVARCHAR(MAX) NULL,
        client_created_at DATETIME2 NOT NULL,
        created_at DATETIME2 NOT NULL CONSTRAINT DF_CheckoutOrders_created_at DEFAULT SYSUTCDATETIME(),
        assigned_at DATETIME2 NULL,
        active_until DATETIME2 NOT NULL,
        CONSTRAINT UQ_CheckoutOrders_verification_id UNIQUE (verification_id),
        CONSTRAINT FK_CheckoutOrders_Users
            FOREIGN KEY (user_id) REFERENCES dbo.Users (user_id),
        CONSTRAINT FK_CheckoutOrders_AssignedUsers
            FOREIGN KEY (assigned_to_user_id) REFERENCES dbo.Users (user_id)
    );
END;
GO

IF OBJECT_ID(N'dbo.CheckoutOrders', N'U') IS NOT NULL
   AND COL_LENGTH(N'dbo.CheckoutOrders', N'subtotal_amount') IS NULL
BEGIN
    ALTER TABLE dbo.CheckoutOrders
        ADD subtotal_amount DECIMAL(10, 2) NULL;

    EXEC sp_executesql N'
        UPDATE dbo.CheckoutOrders
        SET subtotal_amount = total_amount
        WHERE subtotal_amount IS NULL;
    ';

    EXEC sp_executesql N'
        ALTER TABLE dbo.CheckoutOrders
            ALTER COLUMN subtotal_amount DECIMAL(10, 2) NOT NULL;
    ';
END;
GO

IF OBJECT_ID(N'dbo.CheckoutOrders', N'U') IS NOT NULL
   AND COL_LENGTH(N'dbo.CheckoutOrders', N'redeemed_points') IS NULL
BEGIN
    ALTER TABLE dbo.CheckoutOrders
        ADD redeemed_points INT NULL;

    EXEC sp_executesql N'
        UPDATE dbo.CheckoutOrders
        SET redeemed_points = 0
        WHERE redeemed_points IS NULL;
    ';

    EXEC sp_executesql N'
        ALTER TABLE dbo.CheckoutOrders
            ALTER COLUMN redeemed_points INT NOT NULL;
    ';
END;
GO

IF OBJECT_ID(N'dbo.CheckoutOrders', N'U') IS NOT NULL
   AND COL_LENGTH(N'dbo.CheckoutOrders', N'redeemed_amount') IS NULL
BEGIN
    ALTER TABLE dbo.CheckoutOrders
        ADD redeemed_amount DECIMAL(10, 2) NULL;

    EXEC sp_executesql N'
        UPDATE dbo.CheckoutOrders
        SET redeemed_amount = 0
        WHERE redeemed_amount IS NULL;
    ';

    EXEC sp_executesql N'
        ALTER TABLE dbo.CheckoutOrders
            ALTER COLUMN redeemed_amount DECIMAL(10, 2) NOT NULL;
    ';
END;
GO

IF OBJECT_ID(N'dbo.CheckoutOrders', N'U') IS NOT NULL
   AND COL_LENGTH(N'dbo.CheckoutOrders', N'active_until') IS NULL
BEGIN
    ALTER TABLE dbo.CheckoutOrders
        ADD active_until DATETIME2 NULL;

    EXEC sp_executesql N'
        UPDATE dbo.CheckoutOrders
        SET active_until = DATEADD(MINUTE, eta_minutes, created_at)
        WHERE active_until IS NULL;
    ';

    EXEC sp_executesql N'
        ALTER TABLE dbo.CheckoutOrders
            ALTER COLUMN active_until DATETIME2 NOT NULL;
    ';
END;
GO

IF OBJECT_ID(N'dbo.CheckoutOrders', N'U') IS NOT NULL
   AND COL_LENGTH(N'dbo.CheckoutOrders', N'processing_status') IS NULL
BEGIN
    ALTER TABLE dbo.CheckoutOrders
        ADD processing_status NVARCHAR(50) NULL;

    EXEC sp_executesql N'
        UPDATE dbo.CheckoutOrders
        SET processing_status = CASE
            WHEN LOWER(LTRIM(RTRIM(status))) = N''completed'' THEN N''completed''
            ELSE N''unassigned''
        END
        WHERE processing_status IS NULL;
    ';

    EXEC sp_executesql N'
        ALTER TABLE dbo.CheckoutOrders
            ALTER COLUMN processing_status NVARCHAR(50) NOT NULL;
    ';
END;
GO

IF OBJECT_ID(N'dbo.Users', N'U') IS NOT NULL
   AND OBJECT_ID(N'dbo.CheckoutOrders', N'U') IS NOT NULL
   AND COL_LENGTH(N'dbo.CheckoutOrders', N'assigned_to_user_id') IS NULL
BEGIN
    ALTER TABLE dbo.CheckoutOrders
        ADD assigned_to_user_id INT NULL;

    ALTER TABLE dbo.CheckoutOrders
        ADD CONSTRAINT FK_CheckoutOrders_AssignedUsers
            FOREIGN KEY (assigned_to_user_id) REFERENCES dbo.Users (user_id);
END;
GO

IF OBJECT_ID(N'dbo.CheckoutOrders', N'U') IS NOT NULL
   AND COL_LENGTH(N'dbo.CheckoutOrders', N'assigned_at') IS NULL
BEGIN
    ALTER TABLE dbo.CheckoutOrders
        ADD assigned_at DATETIME2 NULL;
END;
GO

IF OBJECT_ID(N'dbo.CheckoutOrders', N'U') IS NOT NULL
   AND COL_LENGTH(N'dbo.CheckoutOrders', N'receipt_confirmation_requested_at') IS NULL
BEGIN
    ALTER TABLE dbo.CheckoutOrders
        ADD receipt_confirmation_requested_at DATETIME2 NULL;
END;
GO

IF OBJECT_ID(N'dbo.CheckoutOrders', N'U') IS NOT NULL
   AND COL_LENGTH(N'dbo.CheckoutOrders', N'receipt_confirmed_at') IS NULL
BEGIN
    ALTER TABLE dbo.CheckoutOrders
        ADD receipt_confirmed_at DATETIME2 NULL;
END;
GO

IF OBJECT_ID(N'dbo.CheckoutOrders', N'U') IS NOT NULL
   AND COL_LENGTH(N'dbo.CheckoutOrders', N'support_alert_sent_at') IS NULL
BEGIN
    ALTER TABLE dbo.CheckoutOrders
        ADD support_alert_sent_at DATETIME2 NULL;
END;
GO

IF OBJECT_ID(N'dbo.CheckoutOrders', N'U') IS NOT NULL
   AND COL_LENGTH(N'dbo.CheckoutOrders', N'delivery_extension_count') IS NULL
BEGIN
    ALTER TABLE dbo.CheckoutOrders
        ADD delivery_extension_count INT NULL;

    EXEC sp_executesql N'
        UPDATE dbo.CheckoutOrders
        SET delivery_extension_count = 0
        WHERE delivery_extension_count IS NULL;
    ';

    EXEC sp_executesql N'
        ALTER TABLE dbo.CheckoutOrders
            ALTER COLUMN delivery_extension_count INT NOT NULL;
    ';
END;
GO

IF OBJECT_ID(N'dbo.CheckoutOrders', N'U') IS NOT NULL
   AND NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = N'IX_CheckoutOrders_verification_id'
      AND object_id = OBJECT_ID(N'dbo.CheckoutOrders')
)
BEGIN
    CREATE INDEX IX_CheckoutOrders_verification_id
        ON dbo.CheckoutOrders (verification_id);
END;
GO

IF OBJECT_ID(N'dbo.CheckoutOrders', N'U') IS NOT NULL
   AND NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = N'IX_CheckoutOrders_user_id'
      AND object_id = OBJECT_ID(N'dbo.CheckoutOrders')
)
BEGIN
    CREATE INDEX IX_CheckoutOrders_user_id
        ON dbo.CheckoutOrders (user_id);
END;
GO

IF OBJECT_ID(N'dbo.CheckoutOrders', N'U') IS NOT NULL
   AND NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = N'IX_CheckoutOrders_processing_status'
      AND object_id = OBJECT_ID(N'dbo.CheckoutOrders')
)
BEGIN
    CREATE INDEX IX_CheckoutOrders_processing_status
        ON dbo.CheckoutOrders (processing_status);
END;
GO

IF OBJECT_ID(N'dbo.CheckoutOrders', N'U') IS NOT NULL
   AND NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = N'IX_CheckoutOrders_assigned_to_user_id'
      AND object_id = OBJECT_ID(N'dbo.CheckoutOrders')
)
BEGIN
    CREATE INDEX IX_CheckoutOrders_assigned_to_user_id
        ON dbo.CheckoutOrders (assigned_to_user_id);
END;
GO

IF OBJECT_ID(N'dbo.CheckoutOrders', N'U') IS NOT NULL
   AND OBJECT_ID(N'dbo.CheckoutOrderItems', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.CheckoutOrderItems (
        checkout_order_item_id INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        checkout_order_id INT NOT NULL,
        cart_entry_id INT NOT NULL,
        position_id INT NULL,
        name NVARCHAR(120) NOT NULL,
        description NVARCHAR(MAX) NULL,
        photo_url NVARCHAR(500) NULL,
        calories INT NULL,
        price DECIMAL(10, 2) NULL,
        quantity INT NOT NULL CONSTRAINT DF_CheckoutOrderItems_quantity DEFAULT (1),
        CONSTRAINT FK_CheckoutOrderItems_CheckoutOrders
            FOREIGN KEY (checkout_order_id) REFERENCES dbo.CheckoutOrders (checkout_order_id)
            ON DELETE CASCADE
    );
END;
GO

IF OBJECT_ID(N'dbo.Users', N'U') IS NOT NULL
   AND OBJECT_ID(N'dbo.CheckoutOrders', N'U') IS NOT NULL
   AND OBJECT_ID(N'dbo.CheckoutSupportAlerts', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.CheckoutSupportAlerts (
        checkout_support_alert_id INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        checkout_order_id INT NOT NULL,
        user_id INT NULL,
        message NVARCHAR(MAX) NOT NULL,
        created_at DATETIME2 NOT NULL CONSTRAINT DF_CheckoutSupportAlerts_created_at DEFAULT SYSUTCDATETIME(),
        CONSTRAINT FK_CheckoutSupportAlerts_CheckoutOrders
            FOREIGN KEY (checkout_order_id) REFERENCES dbo.CheckoutOrders (checkout_order_id)
            ON DELETE CASCADE,
        CONSTRAINT FK_CheckoutSupportAlerts_Users
            FOREIGN KEY (user_id) REFERENCES dbo.Users (user_id)
    );
END;
GO

IF OBJECT_ID(N'dbo.Users', N'U') IS NOT NULL
   AND OBJECT_ID(N'dbo.CheckoutOrders', N'U') IS NOT NULL
   AND OBJECT_ID(N'dbo.CheckoutOrderMessages', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.CheckoutOrderMessages (
        checkout_order_message_id INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        checkout_order_id INT NOT NULL,
        sender_user_id INT NULL,
        sender_role NVARCHAR(30) NOT NULL,
        author_label NVARCHAR(120) NOT NULL,
        message NVARCHAR(MAX) NOT NULL,
        created_at DATETIME2 NOT NULL CONSTRAINT DF_CheckoutOrderMessages_created_at DEFAULT SYSUTCDATETIME(),
        staff_read_at DATETIME2 NULL,
        CONSTRAINT FK_CheckoutOrderMessages_CheckoutOrders
            FOREIGN KEY (checkout_order_id) REFERENCES dbo.CheckoutOrders (checkout_order_id)
            ON DELETE CASCADE,
        CONSTRAINT FK_CheckoutOrderMessages_Users
            FOREIGN KEY (sender_user_id) REFERENCES dbo.Users (user_id)
    );
END;
GO

IF OBJECT_ID(N'dbo.CheckoutOrderMessages', N'U') IS NOT NULL
   AND NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = N'IX_CheckoutOrderMessages_checkout_order_id'
      AND object_id = OBJECT_ID(N'dbo.CheckoutOrderMessages')
)
BEGIN
    CREATE INDEX IX_CheckoutOrderMessages_checkout_order_id
        ON dbo.CheckoutOrderMessages (checkout_order_id);
END;
GO

IF OBJECT_ID(N'dbo.CheckoutOrderMessages', N'U') IS NOT NULL
   AND NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = N'IX_CheckoutOrderMessages_staff_read_at'
      AND object_id = OBJECT_ID(N'dbo.CheckoutOrderMessages')
)
BEGIN
    CREATE INDEX IX_CheckoutOrderMessages_staff_read_at
        ON dbo.CheckoutOrderMessages (staff_read_at, checkout_order_id);
END;
GO

IF OBJECT_ID(N'dbo.CheckoutSupportAlerts', N'U') IS NOT NULL
   AND NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = N'IX_CheckoutSupportAlerts_checkout_order_id'
      AND object_id = OBJECT_ID(N'dbo.CheckoutSupportAlerts')
)
BEGIN
    CREATE INDEX IX_CheckoutSupportAlerts_checkout_order_id
        ON dbo.CheckoutSupportAlerts (checkout_order_id);
END;
GO

IF OBJECT_ID(N'dbo.CheckoutOrderItems', N'U') IS NOT NULL
   AND NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = N'IX_CheckoutOrderItems_checkout_order_id'
      AND object_id = OBJECT_ID(N'dbo.CheckoutOrderItems')
)
BEGIN
    CREATE INDEX IX_CheckoutOrderItems_checkout_order_id
        ON dbo.CheckoutOrderItems (checkout_order_id);
END;
GO
