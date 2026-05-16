IF OBJECT_ID(N'dbo.Users', N'U') IS NULL
BEGIN
    PRINT N'Pomijam app_runtime_settings.sql, bo tabela dbo.Users jeszcze nie istnieje.';
END;
GO

IF OBJECT_ID(N'dbo.Users', N'U') IS NOT NULL
   AND OBJECT_ID(N'dbo.AppRuntimeSettings', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.AppRuntimeSettings (
        setting_id INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        setting_key NVARCHAR(80) NOT NULL,
        label NVARCHAR(160) NOT NULL,
        decimal_value DECIMAL(10, 2) NOT NULL
            CONSTRAINT DF_AppRuntimeSettings_decimal_value DEFAULT (0),
        updated_by_user_id INT NULL,
        updated_at DATETIME2 NOT NULL
            CONSTRAINT DF_AppRuntimeSettings_updated_at DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT FK_AppRuntimeSettings_Users
            FOREIGN KEY (updated_by_user_id) REFERENCES dbo.Users (user_id)
    );
END;
GO

IF OBJECT_ID(N'dbo.AppRuntimeSettings', N'U') IS NOT NULL
   AND NOT EXISTS (
    SELECT 1
    FROM sys.columns
    WHERE object_id = OBJECT_ID(N'dbo.AppRuntimeSettings')
      AND name = N'string_value'
)
BEGIN
    ALTER TABLE dbo.AppRuntimeSettings
        ADD string_value NVARCHAR(500) NULL;
END;
GO

IF OBJECT_ID(N'dbo.AppRuntimeSettings', N'U') IS NOT NULL
   AND NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = N'UQ_AppRuntimeSettings_setting_key'
      AND object_id = OBJECT_ID(N'dbo.AppRuntimeSettings')
)
BEGIN
    CREATE UNIQUE INDEX UQ_AppRuntimeSettings_setting_key
        ON dbo.AppRuntimeSettings (setting_key);
END;
GO

IF OBJECT_ID(N'dbo.MenuPositions', N'U') IS NOT NULL
BEGIN
    IF EXISTS (
        SELECT 1
        FROM sys.columns
        WHERE object_id = OBJECT_ID(N'dbo.MenuPositions')
          AND name = N'price'
          AND system_type_id IN (106, 108)
          AND scale = 0
    )
    BEGIN
        ALTER TABLE dbo.MenuPositions
            ALTER COLUMN price DECIMAL(10, 2) NULL;
    END;
END;
GO

IF OBJECT_ID(N'dbo.AppRuntimeSettings', N'U') IS NOT NULL
BEGIN
    MERGE dbo.AppRuntimeSettings AS target
    USING (
        SELECT
            N'delivery_minimum_amount' AS setting_key,
            N'Minimalna wartosc zamowienia z dostawa' AS label,
            CAST(20.00 AS DECIMAL(10, 2)) AS decimal_value,
            CAST(NULL AS NVARCHAR(500)) AS string_value
        UNION ALL
        SELECT
            N'delivery_radius_km' AS setting_key,
            N'Promien dostawy' AS label,
            CAST(8.00 AS DECIMAL(10, 2)) AS decimal_value,
            CAST(NULL AS NVARCHAR(500)) AS string_value
        UNION ALL
        SELECT
            N'delivery_origin_address' AS setting_key,
            N'Adres lokalu dla dostaw' AS label,
            CAST(0.00 AS DECIMAL(10, 2)) AS decimal_value,
            CAST(N'' AS NVARCHAR(500)) AS string_value
    ) AS source
        ON target.setting_key = source.setting_key
    WHEN MATCHED THEN
        UPDATE SET
            label = source.label
    WHEN NOT MATCHED THEN
        INSERT (setting_key, label, decimal_value, string_value)
        VALUES (source.setting_key, source.label, source.decimal_value, source.string_value);
END;
GO
