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
        addon_group_key NVARCHAR(40) NOT NULL
            CONSTRAINT DF_MenuAddons_addon_group_key DEFAULT (N'sauce'),
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
   AND COL_LENGTH(N'dbo.MenuAddons', N'addon_group_key') IS NULL
BEGIN
    ALTER TABLE dbo.MenuAddons
    ADD addon_group_key NVARCHAR(40) NULL
        CONSTRAINT DF_MenuAddons_addon_group_key DEFAULT (N'sauce');

    UPDATE dbo.MenuAddons
    SET addon_group_key = N'sauce'
    WHERE addon_group_key IS NULL;

    ALTER TABLE dbo.MenuAddons
    ALTER COLUMN addon_group_key NVARCHAR(40) NOT NULL;
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
            seed.addon_group_key,
            seed.sort_order
        FROM (VALUES
            (N'Pomidory cherry', N'Swieze pomidory cherry do odswiezenia zapiekanki.', CAST(3.00 AS DECIMAL(10, 2)), N'/assets/images/tomatos.png', N'cold', 10),
            (N'Ogorek kiszony', N'Kwaskowy ogorek kiszony do przelamania sera i miesa.', CAST(3.00 AS DECIMAL(10, 2)), NULL, N'cold', 20),
            (N'Zurawina', N'Slodko-kwasna zurawina do bardziej kontrastowego smaku.', CAST(3.00 AS DECIMAL(10, 2)), NULL, N'cold', 30),
            (N'Prazona cebulka', N'Chrupiaca prazona cebulka dla dodatkowej tekstury i aromatu.', CAST(2.50 AS DECIMAL(10, 2)), N'/assets/images/crispyOnions.png', N'cold', 40),
            (N'Oliwki', N'Lekko slone oliwki, ktore podbijaja smak sera i pieczywa.', CAST(3.00 AS DECIMAL(10, 2)), NULL, N'cold', 50),
            (N'Salami', N'Wyraziste salami zapiekane razem z pozycja.', CAST(4.00 AS DECIMAL(10, 2)), NULL, N'hot', 60),
            (N'Szynka', N'Klasyczna szynka jako cieply dodatek do zapiekanki.', CAST(4.00 AS DECIMAL(10, 2)), NULL, N'hot', 70),
            (N'Kielbasa', N'Pieczona kielbasa dla bardziej konkretnego, miesnego profilu.', CAST(4.00 AS DECIMAL(10, 2)), NULL, N'hot', 80),
            (N'Ananas', N'Slodki ananas do bardziej kontrastowej kompozycji.', CAST(3.00 AS DECIMAL(10, 2)), NULL, N'hot', 90),
            (N'Cebula czerwona', N'Cienko krojona czerwona cebula, ktora dobrze siada na cieplo.', CAST(3.00 AS DECIMAL(10, 2)), NULL, N'hot', 100),
            (N'Bulka', N'Miekka bulka do zestawu z udkami.', CAST(3.00 AS DECIMAL(10, 2)), NULL, N'side', 110),
            (N'Pikle', N'Kwaskowe pikle do przelamania ciezszego smaku kurczaka.', CAST(3.00 AS DECIMAL(10, 2)), NULL, N'side', 120),
            (N'Surowka kolorowa', N'Swieza surowka jako lekki, chrupiacy kontrast do udek.', CAST(4.00 AS DECIMAL(10, 2)), N'/assets/images/colorSalad.png', N'side', 130),
            (N'Ketchup', N'Klasyczny ketchup.', CAST(1.50 AS DECIMAL(10, 2)), N'/assets/images/ketchup.png', N'sauce', 140),
            (N'Majonez', N'Gesty, lagodny majonez do klasycznych polaczen.', CAST(1.50 AS DECIMAL(10, 2)), NULL, N'sauce', 150),
            (N'Musztarda', N'Wyrazista musztarda do kurczaka, frytek i zapiekanek.', CAST(1.50 AS DECIMAL(10, 2)), NULL, N'sauce', 160),
            (N'Sos tysiaca wysp', N'Lagodny, kremowy sos do bogatszej kompozycji.', CAST(2.50 AS DECIMAL(10, 2)), N'/assets/images/thousandIslandsSauce.png', N'sauce', 170),
            (N'Sos czosnkowy', N'Lagodny, kremowy sos czosnkowy do frytek, udek i cieplejszych pozycji.', CAST(2.50 AS DECIMAL(10, 2)), NULL, N'sauce', 180),
            (N'Sos ostry', N'Pikantny sos dla ostrzejszego finiszu.', CAST(2.50 AS DECIMAL(10, 2)), NULL, N'sauce', 190),
            (N'Remoulada', N'Kremowa remoulada z ziolowym finiszem.', CAST(2.50 AS DECIMAL(10, 2)), NULL, N'sauce', 200),
            (N'Sos BBQ', N'Dymny sos do kurczaka i bardziej grillowego profilu.', CAST(2.00 AS DECIMAL(10, 2)), N'/assets/images/bbqSauce.png', N'sauce', 210),
            (N'Sos buffalo', N'Lekko pikantny sos dla bardziej wyrazistego profilu udek.', CAST(2.50 AS DECIMAL(10, 2)), NULL, N'sauce', 220),
            (N'Sos miodowo-musztardowy', N'Slodko-wytrawny sos, ktory dobrze siada z pieczonym kurczakiem.', CAST(2.50 AS DECIMAL(10, 2)), NULL, N'sauce', 230)
        ) AS seed(name, description, price, photo_url, addon_group_key, sort_order)
    )
    MERGE dbo.MenuAddons AS target
    USING AddonSeed AS source
        ON target.name = source.name
    WHEN MATCHED THEN
        UPDATE SET
            description = source.description,
            price = source.price,
            photo_url = source.photo_url,
            addon_group_key = source.addon_group_key,
            sort_order = source.sort_order,
            is_active = 1
    WHEN NOT MATCHED THEN
        INSERT (name, description, price, photo_url, addon_group_key, sort_order, is_active)
        VALUES (
            source.name,
            source.description,
            source.price,
            source.photo_url,
            source.addon_group_key,
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
        WHERE (
                LOWER(ISNULL(position_type, N'')) LIKE N'%zapiek%'
            AND LOWER(ISNULL(position_type, N'')) NOT LIKE N'%frozen%'
            AND LOWER(ISNULL(position_type, N'')) NOT LIKE N'%mroz%'
        )
           OR (
                LOWER(ISNULL(name, N'')) LIKE N'%zapiek%'
            AND LOWER(ISNULL(name, N'')) NOT LIKE N'%mroz%'
        )
    ),
    KidsPositions AS (
        SELECT position_id
        FROM dbo.MenuPositions
        WHERE LOWER(ISNULL(position_type, N'')) LIKE N'%kids%'
           OR LOWER(ISNULL(name, N'')) LIKE N'%kids%'
           OR LOWER(ISNULL(name, N'')) LIKE N'%dziec%'
    ),
    UdkaPositions AS (
        SELECT position_id
        FROM dbo.MenuPositions
        WHERE LOWER(ISNULL(position_type, N'')) LIKE N'%udk%'
           OR LOWER(ISNULL(name, N'')) LIKE N'%udk%'
           OR LOWER(ISNULL(name, N'')) LIKE N'%kurczak%'
           OR LOWER(ISNULL(name, N'')) LIKE N'%chicken%'
    ),
    FriesPositions AS (
        SELECT position_id
        FROM dbo.MenuPositions
        WHERE LOWER(ISNULL(position_type, N'')) LIKE N'%dodatek%'
           OR LOWER(ISNULL(name, N'')) LIKE N'%frytk%'
           OR LOWER(ISNULL(photo_url, N'')) LIKE N'%fries%'
    ),
    AddonCatalog AS (
        SELECT
            seed.target_group,
            seed.addon_name,
            seed.is_default,
            seed.default_quantity
        FROM (VALUES
            (N'zapiekanki', N'Pomidory cherry', CAST(0 AS BIT), 0),
            (N'zapiekanki', N'Ogorek kiszony', CAST(0 AS BIT), 0),
            (N'zapiekanki', N'Zurawina', CAST(0 AS BIT), 0),
            (N'zapiekanki', N'Prazona cebulka', CAST(0 AS BIT), 0),
            (N'zapiekanki', N'Oliwki', CAST(0 AS BIT), 0),
            (N'zapiekanki', N'Salami', CAST(0 AS BIT), 0),
            (N'zapiekanki', N'Szynka', CAST(0 AS BIT), 0),
            (N'zapiekanki', N'Kielbasa', CAST(0 AS BIT), 0),
            (N'zapiekanki', N'Ananas', CAST(0 AS BIT), 0),
            (N'zapiekanki', N'Cebula czerwona', CAST(0 AS BIT), 0),
            (N'zapiekanki', N'Ketchup', CAST(0 AS BIT), 0),
            (N'zapiekanki', N'Majonez', CAST(0 AS BIT), 0),
            (N'zapiekanki', N'Musztarda', CAST(0 AS BIT), 0),
            (N'zapiekanki', N'Sos tysiaca wysp', CAST(0 AS BIT), 0),
            (N'zapiekanki', N'Sos czosnkowy', CAST(0 AS BIT), 0),
            (N'zapiekanki', N'Sos ostry', CAST(0 AS BIT), 0),
            (N'zapiekanki', N'Remoulada', CAST(0 AS BIT), 0),
            (N'udka', N'Bulka', CAST(0 AS BIT), 0),
            (N'udka', N'Pikle', CAST(0 AS BIT), 0),
            (N'udka', N'Surowka kolorowa', CAST(0 AS BIT), 0),
            (N'udka', N'Ketchup', CAST(0 AS BIT), 0),
            (N'udka', N'Majonez', CAST(0 AS BIT), 0),
            (N'udka', N'Musztarda', CAST(0 AS BIT), 0),
            (N'udka', N'Sos BBQ', CAST(0 AS BIT), 0),
            (N'udka', N'Sos czosnkowy', CAST(0 AS BIT), 0),
            (N'udka', N'Sos buffalo', CAST(0 AS BIT), 0),
            (N'udka', N'Sos miodowo-musztardowy', CAST(0 AS BIT), 0),
            (N'udka', N'Sos ostry', CAST(0 AS BIT), 0),
            (N'udka', N'Remoulada', CAST(0 AS BIT), 0),
            (N'frytki', N'Ketchup', CAST(0 AS BIT), 0),
            (N'frytki', N'Majonez', CAST(0 AS BIT), 0),
            (N'frytki', N'Musztarda', CAST(0 AS BIT), 0),
            (N'frytki', N'Sos czosnkowy', CAST(0 AS BIT), 0),
            (N'frytki', N'Sos ostry', CAST(0 AS BIT), 0),
            (N'frytki', N'Remoulada', CAST(0 AS BIT), 0)
        ) AS seed(target_group, addon_name, is_default, default_quantity)
    ),
    TrackedPositions AS (
        SELECT position_id FROM ZapiekankaPositions
        UNION
        SELECT position_id FROM KidsPositions
        UNION
        SELECT position_id FROM UdkaPositions
        UNION
        SELECT position_id FROM FriesPositions
    ),
    AddonLinks AS (
        SELECT
            zp.position_id,
            ma.addon_id,
            addon.is_default,
            addon.default_quantity
        FROM ZapiekankaPositions AS zp
        JOIN AddonCatalog AS addon
            ON addon.target_group = N'zapiekanki'
        JOIN dbo.MenuAddons AS ma
            ON ma.name = addon.addon_name
        UNION ALL
        SELECT
            kp.position_id,
            ma.addon_id,
            addon.is_default,
            addon.default_quantity
        FROM KidsPositions AS kp
        JOIN AddonCatalog AS addon
            ON addon.target_group = N'zapiekanki'
        JOIN dbo.MenuAddons AS ma
            ON ma.name = addon.addon_name
        UNION ALL
        SELECT
            up.position_id,
            ma.addon_id,
            addon.is_default,
            addon.default_quantity
        FROM UdkaPositions AS up
        JOIN AddonCatalog AS addon
            ON addon.target_group = N'udka'
        JOIN dbo.MenuAddons AS ma
            ON ma.name = addon.addon_name
        UNION ALL
        SELECT
            fp.position_id,
            ma.addon_id,
            addon.is_default,
            addon.default_quantity
        FROM FriesPositions AS fp
        JOIN AddonCatalog AS addon
            ON addon.target_group = N'frytki'
        JOIN dbo.MenuAddons AS ma
            ON ma.name = addon.addon_name
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
        )
    WHEN NOT MATCHED BY SOURCE
         AND target.position_id IN (SELECT position_id FROM TrackedPositions) THEN
        DELETE;
END;
GO

IF OBJECT_ID(N'dbo.MenuAddons', N'U') IS NOT NULL
   AND OBJECT_ID(N'dbo.MenuPositionAddons', N'U') IS NOT NULL
BEGIN
    ;WITH SeedNames AS (
        SELECT seed.name
        FROM (VALUES
            (N'Pomidory cherry'),
            (N'Ogorek kiszony'),
            (N'Zurawina'),
            (N'Prazona cebulka'),
            (N'Oliwki'),
            (N'Salami'),
            (N'Szynka'),
            (N'Kielbasa'),
            (N'Ananas'),
            (N'Cebula czerwona'),
            (N'Bulka'),
            (N'Pikle'),
            (N'Surowka kolorowa'),
            (N'Ketchup'),
            (N'Majonez'),
            (N'Musztarda'),
            (N'Sos tysiaca wysp'),
            (N'Sos czosnkowy'),
            (N'Sos ostry'),
            (N'Remoulada'),
            (N'Sos BBQ'),
            (N'Sos buffalo'),
            (N'Sos miodowo-musztardowy')
        ) AS seed(name)
    )
    DELETE addon
    FROM dbo.MenuAddons AS addon
    WHERE addon.name NOT IN (SELECT name FROM SeedNames)
      AND NOT EXISTS (
            SELECT 1
            FROM dbo.MenuPositionAddons AS link
            WHERE link.addon_id = addon.addon_id
      );
END;
GO
