IF OBJECT_ID(N'dbo.Users', N'U') IS NULL
BEGIN
    PRINT N'Pomijam reference_seed_v2026_06_03.sql, bo tabela dbo.Users jeszcze nie istnieje.';
END;
GO

IF OBJECT_ID(N'dbo.Users', N'U') IS NOT NULL
BEGIN
    IF OBJECT_ID(N'dbo.SeedMigrations', N'U') IS NULL
    BEGIN
        CREATE TABLE dbo.SeedMigrations (
            seed_id INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
            seed_version NVARCHAR(64) NOT NULL UNIQUE,
            applied_at DATETIME2 NOT NULL DEFAULT (SYSUTCDATETIME())
        );
    END;
END;
GO

IF OBJECT_ID(N'dbo.SeedMigrations', N'U') IS NOT NULL
   AND NOT EXISTS (
    SELECT 1
    FROM dbo.SeedMigrations
    WHERE seed_version = N'reference-v2026.06.03.2'
)
BEGIN
    IF OBJECT_ID(N'dbo.AppRuntimeSettings', N'U') IS NOT NULL
    BEGIN
        ;WITH RuntimeSeed AS (
            SELECT *
            FROM (VALUES
                (N'delivery_minimum_amount', N'Minimalna wartosc zamowienia z dostawa', CAST(50.00 AS DECIMAL(10, 2)), CAST(NULL AS NVARCHAR(500))),
                (N'delivery_radius_km', N'Promien dostawy', CAST(5.00 AS DECIMAL(10, 2)), CAST(NULL AS NVARCHAR(500))),
                (N'delivery_origin_address', N'Adres lokalu dla dostaw', CAST(0.00 AS DECIMAL(10, 2)), CAST(N'Z pol Metra Ciete, Zapiekanki z Pieca i Udka z Rozna, 87/89, Radzyminska, Targowek Mieszkaniowy, Targowek, Warszawa, wojewodztwo mazowieckie, 03-512, Polska' AS NVARCHAR(500))),
                (N'kitchen_eta_override_minutes', N'Reczny narzut czasu realizacji przez kuchnie (min)', CAST(0.00 AS DECIMAL(10, 2)), CAST(NULL AS NVARCHAR(500)))
            ) AS src(setting_key, label, decimal_value, string_value)
        )
        MERGE dbo.AppRuntimeSettings AS target
        USING RuntimeSeed AS source
            ON target.setting_key = source.setting_key
        WHEN MATCHED THEN
            UPDATE SET
                target.label = source.label,
                target.decimal_value = source.decimal_value,
                target.string_value = source.string_value
        WHEN NOT MATCHED THEN
            INSERT (setting_key, label, decimal_value, string_value)
            VALUES (source.setting_key, source.label, source.decimal_value, source.string_value);
    END;
    IF OBJECT_ID(N'dbo.ProductPrepTimeSettings', N'U') IS NOT NULL
    BEGIN
        ;WITH PrepTimeSeed AS (
            SELECT *
            FROM (VALUES
                (N'frytki', N'Frytki', CAST(5 AS INT), 20, CAST(1 AS BIT)),
                (N'lody', N'Lody', CAST(5 AS INT), 30, CAST(1 AS BIT)),
                (N'udka', N'Udka', CAST(40 AS INT), 40, CAST(1 AS BIT)),
                (N'zapiekanki', N'Zapiekanki', CAST(5 AS INT), 10, CAST(1 AS BIT))
            ) AS src(group_key, label, minutes, sort_order, is_active)
        )
        MERGE dbo.ProductPrepTimeSettings AS target
        USING PrepTimeSeed AS source
            ON target.group_key = source.group_key
        WHEN MATCHED THEN
            UPDATE SET
                target.label = source.label,
                target.minutes = source.minutes,
                target.sort_order = source.sort_order,
                target.is_active = source.is_active
        WHEN NOT MATCHED THEN
            INSERT (group_key, label, minutes, sort_order, is_active)
            VALUES (source.group_key, source.label, source.minutes, source.sort_order, source.is_active);
    END;
    IF OBJECT_ID(N'dbo.MenuAddons', N'U') IS NOT NULL
    BEGIN
        ;WITH AddonSeed AS (
            SELECT *
            FROM (VALUES
                (N'Ketchup', N'Klasyczny ketchup.', CAST(1.50 AS DECIMAL(10,2)), N'/assets/images/ketchup.png', N'sauce', 0, CAST(1 AS BIT)),
                (N'Oliwki', N'Lekko slone oliwki do zapiekanek.', CAST(3.00 AS DECIMAL(10,2)), NULL, N'sauce', 0, CAST(1 AS BIT)),
                (N'Pomidory', N'Swieze plasterki pomidora do klasycznej zapiekanki.', CAST(3.00 AS DECIMAL(10,2)), N'/assets/images/tomatos.png', N'sauce', 0, CAST(1 AS BIT)),
                (N'Prazona cebulka', N'Chrupiaca prazona cebulka.', CAST(2.50 AS DECIMAL(10,2)), N'/assets/images/crispyOnions.png', N'sauce', 0, CAST(1 AS BIT)),
                (N'Sos BBQ', N'Dymny sos barbecue.', CAST(2.00 AS DECIMAL(10,2)), N'/assets/images/bbqSauce.png', N'sauce', 0, CAST(1 AS BIT)),
                (N'Sos tysiaca wysp', N'Kremowy sos tysiaca wysp.', CAST(2.50 AS DECIMAL(10,2)), N'/assets/images/thousandIslandsSauce.png', N'sauce', 0, CAST(1 AS BIT)),
                (N'Surowka kolorowa', N'Lekka surowka do zapiekanki.', CAST(4.00 AS DECIMAL(10,2)), N'/assets/images/colorSalad.png', N'sauce', 0, CAST(1 AS BIT))
            ) AS src(name, description, price, photo_url, addon_group_key, sort_order, is_active)
        )
        MERGE dbo.MenuAddons AS target
        USING AddonSeed AS source
            ON target.name = source.name
        WHEN MATCHED THEN
            UPDATE SET
                target.description = source.description,
                target.price = source.price,
                target.photo_url = source.photo_url,
                target.addon_group_key = source.addon_group_key,
                target.sort_order = source.sort_order,
                target.is_active = source.is_active
        WHEN NOT MATCHED THEN
            INSERT (name, description, price, photo_url, addon_group_key, sort_order, is_active)
            VALUES (source.name, source.description, source.price, source.photo_url, source.addon_group_key, source.sort_order, source.is_active);
    END;
    IF OBJECT_ID(N'dbo.MenuPositions', N'U') IS NOT NULL
       AND OBJECT_ID(N'dbo.MenuAddons', N'U') IS NOT NULL
       AND OBJECT_ID(N'dbo.MenuPositionAddons', N'U') IS NOT NULL
    BEGIN
        MERGE dbo.MenuPositionAddons AS target
        USING (
            SELECT
                mp.position_id,
                ma.addon_id,
                CAST(1 AS BIT) AS is_default,
                CAST(1 AS INT) AS default_quantity
            FROM (
                SELECT N'Pieczarka 50cm' AS position_name, N'Oliwki' AS addon_name
                UNION ALL SELECT N'Pieczarka 50cm', N'Prazona cebulka'
                UNION ALL SELECT N'Salame 50cm', N'Oliwki'
                UNION ALL SELECT N'Salame 50cm', N'Prazona cebulka'
                UNION ALL SELECT N'Jalapeno Salame 50cm', N'Oliwki'
                UNION ALL SELECT N'Jalapeno Salame 50cm', N'Prazona cebulka'
                UNION ALL SELECT N'Serowa 50cm', N'Oliwki'
                UNION ALL SELECT N'Serowa 50cm', N'Prazona cebulka'
                UNION ALL SELECT N'Szynka 50cm', N'Oliwki'
                UNION ALL SELECT N'Szynka 50cm', N'Prazona cebulka'
                UNION ALL SELECT N'Goralska 50cm', N'Oliwki'
                UNION ALL SELECT N'Goralska 50cm', N'Prazona cebulka'
                UNION ALL SELECT N'Szarpana 50cm', N'Oliwki'
                UNION ALL SELECT N'Szarpana 50cm', N'Prazona cebulka'
                UNION ALL SELECT N'Rukola 50cm', N'Oliwki'
                UNION ALL SELECT N'Rukola 50cm', N'Prazona cebulka'
            ) AS seed
            JOIN dbo.MenuPositions AS mp
                ON mp.name = seed.position_name
            JOIN dbo.MenuAddons AS ma
                ON ma.name = seed.addon_name
        ) AS source
            ON target.position_id = source.position_id
           AND target.addon_id = source.addon_id
        WHEN MATCHED THEN
            UPDATE SET
                target.is_default = source.is_default,
                target.default_quantity = source.default_quantity
        WHEN NOT MATCHED THEN
            INSERT (position_id, addon_id, is_default, default_quantity)
            VALUES (source.position_id, source.addon_id, source.is_default, source.default_quantity);
    END;

    INSERT INTO dbo.SeedMigrations (seed_version) VALUES (N'reference-v2026.06.03.2');
END;
GO
