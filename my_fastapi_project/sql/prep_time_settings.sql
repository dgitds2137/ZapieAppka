IF OBJECT_ID(N'dbo.Users', N'U') IS NULL
BEGIN
    PRINT N'Pomijam prep_time_settings.sql, bo tabela dbo.Users jeszcze nie istnieje.';
END;
GO

IF OBJECT_ID(N'dbo.Users', N'U') IS NOT NULL
   AND OBJECT_ID(N'dbo.ProductPrepTimeSettings', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ProductPrepTimeSettings (
        setting_id INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        group_key NVARCHAR(50) NOT NULL,
        label NVARCHAR(120) NOT NULL,
        minutes INT NOT NULL
            CONSTRAINT DF_ProductPrepTimeSettings_minutes DEFAULT (15),
        sort_order INT NOT NULL
            CONSTRAINT DF_ProductPrepTimeSettings_sort_order DEFAULT (0),
        is_active BIT NOT NULL
            CONSTRAINT DF_ProductPrepTimeSettings_is_active DEFAULT (1),
        updated_by_user_id INT NULL,
        updated_at DATETIME2 NOT NULL
            CONSTRAINT DF_ProductPrepTimeSettings_updated_at DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT FK_ProductPrepTimeSettings_Users
            FOREIGN KEY (updated_by_user_id) REFERENCES dbo.Users (user_id)
    );
END;
GO

IF OBJECT_ID(N'dbo.ProductPrepTimeSettings', N'U') IS NOT NULL
   AND NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = N'UQ_ProductPrepTimeSettings_group_key'
      AND object_id = OBJECT_ID(N'dbo.ProductPrepTimeSettings')
)
BEGIN
    CREATE UNIQUE INDEX UQ_ProductPrepTimeSettings_group_key
        ON dbo.ProductPrepTimeSettings (group_key);
END;
GO

IF OBJECT_ID(N'dbo.ProductPrepTimeSettings', N'U') IS NOT NULL
BEGIN
    ;WITH PrepTimeSeed AS (
        SELECT
            seed.group_key,
            seed.label,
            seed.minutes,
            seed.sort_order,
            CAST(1 AS BIT) AS is_active
        FROM (VALUES
            (N'zapiekanki', N'Zapiekanki', 15, 10),
            (N'frytki', N'Frytki', 12, 20),
            (N'lody', N'Lody', 2, 30),
            (N'udka', N'Udka', 20, 40)
        ) AS seed(group_key, label, minutes, sort_order)
    )
    MERGE dbo.ProductPrepTimeSettings AS target
    USING PrepTimeSeed AS source
        ON target.group_key = source.group_key
    WHEN MATCHED THEN
        UPDATE SET
            label = source.label,
            sort_order = source.sort_order
    WHEN NOT MATCHED THEN
        INSERT (group_key, label, minutes, sort_order, is_active)
        VALUES (
            source.group_key,
            source.label,
            source.minutes,
            source.sort_order,
            source.is_active
        );
END;
GO
