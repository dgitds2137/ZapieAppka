IF OBJECT_ID(N'dbo.MenuAddons', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.MenuAddons (
        addon_id INT IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_MenuAddons PRIMARY KEY,
        name NVARCHAR(120) NOT NULL,
        description NVARCHAR(500) NULL,
        price DECIMAL(10, 2) NOT NULL
            CONSTRAINT DF_MenuAddons_price DEFAULT (0),
        photo_url NVARCHAR(500) NULL,
        sort_order INT NOT NULL
            CONSTRAINT DF_MenuAddons_sort_order DEFAULT (0),
        is_active BIT NOT NULL
            CONSTRAINT DF_MenuAddons_is_active DEFAULT (1),
        created_at DATETIME2 NOT NULL
            CONSTRAINT DF_MenuAddons_created_at DEFAULT (SYSUTCDATETIME())
    );
END;
GO

IF OBJECT_ID(N'dbo.MenuAddons', N'U') IS NOT NULL
   AND NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.MenuAddons')
      AND name = N'UQ_MenuAddons_name'
)
BEGIN
    CREATE UNIQUE INDEX UQ_MenuAddons_name
        ON dbo.MenuAddons (name);
END;
GO

IF OBJECT_ID(N'dbo.MenuPositions', N'U') IS NULL
BEGIN
    PRINT N'Pomijam tabele powiazan dodatkow, bo dbo.MenuPositions jeszcze nie istnieje.';
END;
GO

IF OBJECT_ID(N'dbo.MenuPositions', N'U') IS NOT NULL
   AND OBJECT_ID(N'dbo.MenuAddons', N'U') IS NOT NULL
   AND OBJECT_ID(N'dbo.MenuPositionAddons', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.MenuPositionAddons (
        menu_position_addon_id INT IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_MenuPositionAddons PRIMARY KEY,
        position_id INT NOT NULL,
        addon_id INT NOT NULL,
        is_default BIT NOT NULL
            CONSTRAINT DF_MenuPositionAddons_is_default DEFAULT (0),
        default_quantity INT NOT NULL
            CONSTRAINT DF_MenuPositionAddons_default_quantity DEFAULT (0),
        created_at DATETIME2 NOT NULL
            CONSTRAINT DF_MenuPositionAddons_created_at DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT FK_MenuPositionAddons_MenuPositions
            FOREIGN KEY (position_id) REFERENCES dbo.MenuPositions (position_id),
        CONSTRAINT FK_MenuPositionAddons_MenuAddons
            FOREIGN KEY (addon_id) REFERENCES dbo.MenuAddons (addon_id)
    );
END;
GO

IF OBJECT_ID(N'dbo.MenuPositionAddons', N'U') IS NOT NULL
   AND NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.MenuPositionAddons')
      AND name = N'UQ_MenuPositionAddons_position_addon'
)
BEGIN
    CREATE UNIQUE INDEX UQ_MenuPositionAddons_position_addon
        ON dbo.MenuPositionAddons (position_id, addon_id);
END;
GO

IF OBJECT_ID(N'dbo.MenuAddons', N'U') IS NOT NULL
BEGIN
    ;WITH AddonSeed AS (
        SELECT
            seed.name,
            seed.description,
            seed.price,
            seed.photo_url,
            seed.sort_order
        FROM (VALUES
            (N'Pomidory', N'Swieze plasterki pomidora do klasycznej zapiekanki.', CAST(3.00 AS DECIMAL(10, 2)), N'/assets/images/tomatos.png', 10),
            (N'Oliwki', N'Lekko slone oliwki do zapiekanek.', CAST(3.00 AS DECIMAL(10, 2)), NULL, 20),
            (N'Prazona cebulka', N'Chrupiaca prazona cebulka.', CAST(2.50 AS DECIMAL(10, 2)), N'/assets/images/crispyOnions.png', 30),
            (N'Sos BBQ', N'Dymny sos barbecue.', CAST(2.00 AS DECIMAL(10, 2)), N'/assets/images/bbqSauce.png', 40),
            (N'Surowka kolorowa', N'Lekka surowka do zapiekanki.', CAST(4.00 AS DECIMAL(10, 2)), N'/assets/images/colorSalad.png', 50),
            (N'Ketchup', N'Klasyczny ketchup.', CAST(1.50 AS DECIMAL(10, 2)), N'/assets/images/ketchup.png', 60),
            (N'Sos tysiaca wysp', N'Kremowy sos tysiaca wysp.', CAST(2.50 AS DECIMAL(10, 2)), N'/assets/images/thousandIslandsSauce.png', 70)
        ) AS seed(name, description, price, photo_url, sort_order)
    )
    MERGE dbo.MenuAddons AS target
    USING AddonSeed AS source
        ON target.name = source.name
    WHEN MATCHED THEN
        UPDATE SET
            description = source.description,
            price = source.price,
            photo_url = source.photo_url,
            sort_order = source.sort_order
    WHEN NOT MATCHED THEN
        INSERT (name, description, price, photo_url, sort_order, is_active)
        VALUES (
            source.name,
            source.description,
            source.price,
            source.photo_url,
            source.sort_order,
            1
        );
END;
GO

IF OBJECT_ID(N'dbo.MenuPositions', N'U') IS NOT NULL
   AND OBJECT_ID(N'dbo.MenuAddons', N'U') IS NOT NULL
   AND OBJECT_ID(N'dbo.MenuPositionAddons', N'U') IS NOT NULL
BEGIN
    ;WITH ZapiekankaPositions AS (
        SELECT position_id
        FROM dbo.MenuPositions
        WHERE LOWER(ISNULL(position_type, N'')) LIKE N'%zapiek%'
           OR LOWER(ISNULL(name, N'')) LIKE N'%zapiek%'
    ),
    AddonLinks AS (
        SELECT
            zp.position_id,
            ma.addon_id,
            CASE
                WHEN ma.name IN (N'Pomidory', N'Oliwki', N'Prazona cebulka') THEN CAST(1 AS BIT)
                ELSE CAST(0 AS BIT)
            END AS is_default,
            CASE
                WHEN ma.name IN (N'Pomidory', N'Oliwki', N'Prazona cebulka') THEN 1
                ELSE 0
            END AS default_quantity
        FROM ZapiekankaPositions AS zp
        CROSS JOIN dbo.MenuAddons AS ma
    )
    MERGE dbo.MenuPositionAddons AS target
    USING AddonLinks AS source
        ON target.position_id = source.position_id
       AND target.addon_id = source.addon_id
    WHEN MATCHED THEN
        UPDATE SET
            is_default = source.is_default,
            default_quantity = source.default_quantity
    WHEN NOT MATCHED THEN
        INSERT (position_id, addon_id, is_default, default_quantity)
        VALUES (
            source.position_id,
            source.addon_id,
            source.is_default,
            source.default_quantity
        );
END;
GO
