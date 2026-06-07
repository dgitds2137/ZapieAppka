SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;

IF OBJECT_ID(N'dbo.SeedMigrations', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.SeedMigrations (
        seed_id INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        seed_version NVARCHAR(64) NOT NULL UNIQUE,
        applied_at DATETIME2 NOT NULL DEFAULT (SYSUTCDATETIME())
    );
END;

IF OBJECT_ID(N'dbo.SeedMigrations', N'U') IS NOT NULL
   AND NOT EXISTS (
    SELECT 1
    FROM dbo.SeedMigrations
    WHERE seed_version = N'reference-v2026.06.03.2'
)
BEGIN
    IF OBJECT_ID(N'dbo.Users', N'U') IS NOT NULL
       AND OBJECT_ID(N'dbo.MenuPositions', N'U') IS NOT NULL
       AND OBJECT_ID(N'dbo.Orders', N'U') IS NOT NULL
    BEGIN
        IF OBJECT_ID(N'dbo.Notifications', N'U') IS NULL
        BEGIN
            CREATE TABLE dbo.Notifications (
                notification_id INT NOT NULL,
                user_id INT NULL,
                order_id INT NULL,
                message NVARCHAR(255) NULL,
                sent_at DATETIME NULL
            ) ON [PRIMARY];
            ALTER TABLE dbo.Notifications
                ADD CONSTRAINT PK_Notifications PRIMARY KEY CLUSTERED (notification_id ASC)
                    WITH (ONLINE = OFF, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF);
            ALTER TABLE dbo.Notifications ADD DEFAULT ((1)) FOR notification_id;
            ALTER TABLE dbo.Notifications ADD DEFAULT (GETDATE()) FOR sent_at;
            ALTER TABLE dbo.Notifications WITH CHECK ADD CONSTRAINT FK_Notifications_Users
                FOREIGN KEY(user_id) REFERENCES dbo.Users (user_id);
        END;

        IF OBJECT_ID(N'dbo.Payments', N'U') IS NULL
        BEGIN
            CREATE TABLE dbo.Payments (
                payment_id BIGINT IDENTITY(1,1) NOT NULL,
                order_id INT NOT NULL,
                user_id INT NULL,
                provider NVARCHAR(30) NOT NULL,
                ext_order_id NVARCHAR(100) NOT NULL,
                provider_order_id NVARCHAR(100) NULL,
                merchant_pos_id NVARCHAR(50) NULL,
                currency_code CHAR(3) NOT NULL,
                amount INT NOT NULL,
                payment_method NVARCHAR(40) NULL,
                status NVARCHAR(30) NOT NULL,
                provider_status NVARCHAR(40) NULL,
                description NVARCHAR(255) NULL,
                redirect_uri NVARCHAR(1000) NULL,
                continue_url NVARCHAR(1000) NULL,
                notify_url NVARCHAR(1000) NULL,
                buyer_email NVARCHAR(255) NULL,
                buyer_phone NVARCHAR(50) NULL,
                buyer_name NVARCHAR(150) NULL,
                customer_ip NVARCHAR(64) NULL,
                idempotency_key NVARCHAR(100) NULL,
                created_at DATETIME NOT NULL,
                updated_at DATETIME NOT NULL,
                authorized_at DATETIME NULL,
                completed_at DATETIME NULL,
                canceled_at DATETIME NULL,
                failed_at DATETIME NULL,
                error_code NVARCHAR(50) NULL,
                error_message NVARCHAR(1000) NULL
            );
            ALTER TABLE dbo.Payments
                ADD CONSTRAINT PK_Payments PRIMARY KEY CLUSTERED (payment_id ASC)
                    WITH (ONLINE = OFF, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF);
            CREATE UNIQUE NONCLUSTERED INDEX UQ_Payments_ext_order_id ON dbo.Payments (ext_order_id ASC);
            CREATE UNIQUE NONCLUSTERED INDEX IX_Payments_idempotency_key
                ON dbo.Payments (idempotency_key ASC)
                WHERE (idempotency_key IS NOT NULL);
            CREATE NONCLUSTERED INDEX IX_Payments_order_id
                ON dbo.Payments (order_id ASC, created_at DESC);
            CREATE NONCLUSTERED INDEX IX_Payments_provider_order_id
                ON dbo.Payments (provider_order_id ASC);
            CREATE NONCLUSTERED INDEX IX_Payments_status
                ON dbo.Payments (status ASC, provider_status ASC, created_at DESC);
            CREATE NONCLUSTERED INDEX IX_Payments_user_id
                ON dbo.Payments (user_id ASC, created_at DESC);
            ALTER TABLE dbo.Payments ADD DEFAULT ('payu') FOR provider;
            ALTER TABLE dbo.Payments ADD DEFAULT ('PLN') FOR currency_code;
            ALTER TABLE dbo.Payments ADD DEFAULT ('created') FOR status;
            ALTER TABLE dbo.Payments ADD DEFAULT (GETDATE()) FOR created_at;
            ALTER TABLE dbo.Payments ADD DEFAULT (GETDATE()) FOR updated_at;
            ALTER TABLE dbo.Payments WITH CHECK ADD CONSTRAINT FK_Payments_Orders
                FOREIGN KEY (order_id) REFERENCES dbo.Orders (order_id);
            ALTER TABLE dbo.Payments CHECK CONSTRAINT FK_Payments_Orders;
            ALTER TABLE dbo.Payments WITH CHECK ADD CONSTRAINT FK_Payments_Users
                FOREIGN KEY (user_id) REFERENCES dbo.Users (user_id);
            ALTER TABLE dbo.Payments CHECK CONSTRAINT FK_Payments_Users;
            ALTER TABLE dbo.Payments WITH CHECK ADD CONSTRAINT CK_Payments_amount_positive
                CHECK ((amount > 0));
            ALTER TABLE dbo.Payments CHECK CONSTRAINT CK_Payments_amount_positive;
            EXEC sp_executesql N'
                CREATE TRIGGER dbo.TR_Payments_SetUpdatedAt
                ON dbo.Payments
                AFTER UPDATE
                AS
                BEGIN
                    SET NOCOUNT ON;

                    UPDATE p
                    SET updated_at = GETDATE()
                    FROM dbo.Payments p
                    INNER JOIN inserted i
                        ON p.payment_id = i.payment_id;
                END
            ';
        END;

        IF OBJECT_ID(N'dbo.PaymentRefunds', N'U') IS NULL
        BEGIN
            CREATE TABLE dbo.PaymentRefunds (
                refund_id BIGINT IDENTITY(1,1) NOT NULL,
                payment_id BIGINT NOT NULL,
                order_id INT NOT NULL,
                provider NVARCHAR(30) NOT NULL,
                provider_refund_id NVARCHAR(100) NULL,
                amount INT NOT NULL,
                currency_code CHAR(3) NOT NULL,
                status NVARCHAR(30) NOT NULL,
                reason NVARCHAR(500) NULL,
                requested_by NVARCHAR(100) NULL,
                created_at DATETIME NOT NULL,
                updated_at DATETIME NOT NULL,
                completed_at DATETIME NULL,
                failed_at DATETIME NULL,
                error_code NVARCHAR(50) NULL,
                error_message NVARCHAR(1000) NULL
            );
            ALTER TABLE dbo.PaymentRefunds
                ADD CONSTRAINT PK_PaymentRefunds PRIMARY KEY CLUSTERED (refund_id ASC)
                    WITH (ONLINE = OFF, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF);
            CREATE NONCLUSTERED INDEX IX_PaymentRefunds_order_id
                ON dbo.PaymentRefunds (order_id ASC, created_at DESC);
            CREATE NONCLUSTERED INDEX IX_PaymentRefunds_payment_id
                ON dbo.PaymentRefunds (payment_id ASC, created_at DESC);
            ALTER TABLE dbo.PaymentRefunds ADD DEFAULT ('payu') FOR provider;
            ALTER TABLE dbo.PaymentRefunds ADD DEFAULT ('PLN') FOR currency_code;
            ALTER TABLE dbo.PaymentRefunds ADD DEFAULT ('created') FOR status;
            ALTER TABLE dbo.PaymentRefunds ADD DEFAULT (GETDATE()) FOR created_at;
            ALTER TABLE dbo.PaymentRefunds ADD DEFAULT (GETDATE()) FOR updated_at;
            ALTER TABLE dbo.PaymentRefunds WITH CHECK ADD CONSTRAINT FK_PaymentRefunds_Orders
                FOREIGN KEY (order_id) REFERENCES dbo.Orders (order_id);
            ALTER TABLE dbo.PaymentRefunds CHECK CONSTRAINT FK_PaymentRefunds_Orders;
            ALTER TABLE dbo.PaymentRefunds WITH CHECK ADD CONSTRAINT FK_PaymentRefunds_Payments
                FOREIGN KEY (payment_id) REFERENCES dbo.Payments (payment_id);
            ALTER TABLE dbo.PaymentRefunds CHECK CONSTRAINT FK_PaymentRefunds_Payments;
            ALTER TABLE dbo.PaymentRefunds WITH CHECK ADD CONSTRAINT CK_PaymentRefunds_amount_positive
                CHECK ((amount > 0));
            ALTER TABLE dbo.PaymentRefunds CHECK CONSTRAINT CK_PaymentRefunds_amount_positive;

            EXEC sp_executesql N'
                CREATE TRIGGER dbo.TR_PaymentRefunds_SetUpdatedAt
                ON dbo.PaymentRefunds
                AFTER UPDATE
                AS
                BEGIN
                    SET NOCOUNT ON;

                    UPDATE r
                    SET updated_at = GETDATE()
                    FROM dbo.PaymentRefunds r
                    INNER JOIN inserted i
                        ON r.refund_id = i.refund_id;
                END
            ';
        END;

        IF OBJECT_ID(N'dbo.PaymentStatusHistory', N'U') IS NULL
        BEGIN
            CREATE TABLE dbo.PaymentStatusHistory (
                payment_status_history_id BIGINT IDENTITY(1,1) NOT NULL,
                payment_id BIGINT NOT NULL,
                old_status NVARCHAR(30) NULL,
                new_status NVARCHAR(30) NOT NULL,
                old_provider_status NVARCHAR(40) NULL,
                new_provider_status NVARCHAR(40) NULL,
                source NVARCHAR(30) NOT NULL,
                note NVARCHAR(500) NULL,
                created_at DATETIME NOT NULL
            );
            ALTER TABLE dbo.PaymentStatusHistory
                ADD CONSTRAINT PK_PaymentStatusHistory PRIMARY KEY CLUSTERED (payment_status_history_id ASC)
                    WITH (ONLINE = OFF, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF);
            CREATE NONCLUSTERED INDEX IX_PaymentStatusHistory_payment_id
                ON dbo.PaymentStatusHistory (payment_id ASC, created_at DESC);
            ALTER TABLE dbo.PaymentStatusHistory ADD DEFAULT (GETDATE()) FOR created_at;
            ALTER TABLE dbo.PaymentStatusHistory WITH CHECK ADD CONSTRAINT FK_PaymentStatusHistory_Payments
                FOREIGN KEY (payment_id) REFERENCES dbo.Payments (payment_id);
            ALTER TABLE dbo.PaymentStatusHistory CHECK CONSTRAINT FK_PaymentStatusHistory_Payments;
        END;

        IF OBJECT_ID(N'dbo.PaymentWebhooks', N'U') IS NULL
        BEGIN
            CREATE TABLE dbo.PaymentWebhooks (
                payment_webhook_id BIGINT IDENTITY(1,1) NOT NULL,
                provider NVARCHAR(30) NOT NULL,
                payment_id BIGINT NULL,
                order_id INT NULL,
                provider_order_id NVARCHAR(100) NULL,
                ext_order_id NVARCHAR(100) NULL,
                received_at DATETIME NOT NULL,
                headers_json NVARCHAR(MAX) NULL,
                payload_json NVARCHAR(MAX) NOT NULL,
                provider_status NVARCHAR(40) NULL,
                event_type NVARCHAR(50) NULL,
                is_processed BIT NOT NULL,
                processed_at DATETIME NULL,
                processing_attempts INT NOT NULL,
                processing_error NVARCHAR(2000) NULL
            ) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY];
            ALTER TABLE dbo.PaymentWebhooks
                ADD CONSTRAINT PK_PaymentWebhooks PRIMARY KEY CLUSTERED (payment_webhook_id ASC)
                    WITH (ONLINE = OFF, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF);
            CREATE NONCLUSTERED INDEX IX_PaymentWebhooks_ext_order_id
                ON dbo.PaymentWebhooks (ext_order_id ASC, received_at DESC);
            CREATE NONCLUSTERED INDEX IX_PaymentWebhooks_is_processed
                ON dbo.PaymentWebhooks (is_processed ASC, received_at ASC);
            CREATE NONCLUSTERED INDEX IX_PaymentWebhooks_provider_order_id
                ON dbo.PaymentWebhooks (provider_order_id ASC, received_at DESC);
            ALTER TABLE dbo.PaymentWebhooks ADD DEFAULT ('payu') FOR provider;
            ALTER TABLE dbo.PaymentWebhooks ADD DEFAULT (GETDATE()) FOR received_at;
            ALTER TABLE dbo.PaymentWebhooks ADD DEFAULT (0) FOR is_processed;
            ALTER TABLE dbo.PaymentWebhooks ADD DEFAULT (0) FOR processing_attempts;
            ALTER TABLE dbo.PaymentWebhooks WITH CHECK ADD CONSTRAINT FK_PaymentWebhooks_Orders
                FOREIGN KEY (order_id) REFERENCES dbo.Orders (order_id);
            ALTER TABLE dbo.PaymentWebhooks CHECK CONSTRAINT FK_PaymentWebhooks_Orders;
            ALTER TABLE dbo.PaymentWebhooks WITH CHECK ADD CONSTRAINT FK_PaymentWebhooks_Payments
                FOREIGN KEY (payment_id) REFERENCES dbo.Payments (payment_id);
            ALTER TABLE dbo.PaymentWebhooks CHECK CONSTRAINT FK_PaymentWebhooks_Payments;
        END;

        IF OBJECT_ID(N'dbo.PickupPoints', N'U') IS NULL
        BEGIN
            CREATE TABLE dbo.PickupPoints (
                point_id INT NOT NULL,
                name NVARCHAR(100) NULL,
                address NVARCHAR(200) NULL,
                priority_support BIT NULL
            ) ON [PRIMARY];
            ALTER TABLE dbo.PickupPoints
                ADD CONSTRAINT PK_PickupPoints PRIMARY KEY CLUSTERED (point_id ASC)
                    WITH (ONLINE = OFF, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF);
            ALTER TABLE dbo.PickupPoints ADD DEFAULT ((1)) FOR point_id;
            ALTER TABLE dbo.PickupPoints ADD DEFAULT ((0)) FOR priority_support;
        END;

        IF OBJECT_ID(N'dbo.UserFavorites', N'U') IS NULL
        BEGIN
            CREATE TABLE dbo.UserFavorites (
                user_id INT NOT NULL,
                position_id INT NOT NULL
            ) ON [PRIMARY];
            ALTER TABLE dbo.UserFavorites
                ADD CONSTRAINT PK_UserFavorites PRIMARY KEY CLUSTERED (user_id ASC, position_id ASC)
                    WITH (ONLINE = OFF, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF);
            ALTER TABLE dbo.UserFavorites WITH CHECK ADD CONSTRAINT FK_UserFavorites_MenuPositions
                FOREIGN KEY (position_id) REFERENCES dbo.MenuPositions (position_id)
                ON UPDATE CASCADE
                ON DELETE CASCADE;
            ALTER TABLE dbo.UserFavorites CHECK CONSTRAINT FK_UserFavorites_MenuPositions;
            ALTER TABLE dbo.UserFavorites WITH CHECK ADD CONSTRAINT FK_UserFavorites_Users
                FOREIGN KEY (user_id) REFERENCES dbo.Users (user_id)
                ON UPDATE CASCADE
                ON DELETE CASCADE;
            ALTER TABLE dbo.UserFavorites CHECK CONSTRAINT FK_UserFavorites_Users;
        END;
    END;

    INSERT INTO dbo.SeedMigrations (seed_version) VALUES (N'reference-v2026.06.03.2');
END;
