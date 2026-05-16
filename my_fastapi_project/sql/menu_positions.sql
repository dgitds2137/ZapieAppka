IF OBJECT_ID(N'dbo.MenuPositions', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.MenuPositions (
        position_id INT IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_MenuPositions PRIMARY KEY,
        position_type NVARCHAR(50) NULL,
        name NVARCHAR(80) NULL,
        weight INT NULL,
        calories INT NULL,
        price DECIMAL(18, 0) NULL,
        description NVARCHAR(MAX) NULL,
        photo_url NVARCHAR(MAX) NULL,
        is_active BIT NOT NULL
            CONSTRAINT DF_MenuPositions_is_active DEFAULT (1)
    );
END;
GO

IF COL_LENGTH(N'dbo.MenuPositions', N'is_active') IS NULL
BEGIN
    ALTER TABLE dbo.MenuPositions
        ADD is_active BIT NULL;

    EXEC sp_executesql N'
        UPDATE dbo.MenuPositions
        SET is_active = 1
        WHERE is_active IS NULL;
    ';

    EXEC sp_executesql N'
        ALTER TABLE dbo.MenuPositions
            ALTER COLUMN is_active BIT NOT NULL;
    ';
END;
GO

IF OBJECT_ID(N'dbo.MenuPositions', N'U') IS NOT NULL
BEGIN
    UPDATE dbo.MenuPositions
    SET is_active = 0
    WHERE name LIKE N'%25cm%'
      AND LOWER(ISNULL(position_type, N'')) NOT LIKE N'%kids%';

    UPDATE target
    SET
        target.name = source.new_name,
        target.weight = source.weight,
        target.calories = source.calories,
        target.price = source.price
    FROM dbo.MenuPositions AS target
    INNER JOIN (VALUES
        (N'Szynka 25cm', N'Szynka 50cm', 200, 400, CAST(40 AS DECIMAL(18, 0))),
        (N'Pieczarka 25cm', N'Pieczarka 50cm', 200, 400, CAST(40 AS DECIMAL(18, 0))),
        (N'Salame 25cm', N'Salame 50cm', 200, 200, CAST(36 AS DECIMAL(18, 0))),
        (N'Jalapeno Salame 25cm', N'Jalapeno Salame 50cm', 200, 200, CAST(36 AS DECIMAL(18, 0))),
        (N'Serowa 25cm', N'Serowa 50cm', 200, 200, CAST(36 AS DECIMAL(18, 0)))
    ) AS source(old_name, new_name, weight, calories, price)
        ON target.name = source.old_name
    WHERE NOT EXISTS (
        SELECT 1
        FROM dbo.MenuPositions AS existing
        WHERE existing.name = source.new_name
    );

    UPDATE target
    SET
        target.name = source.new_name,
        target.weight = source.weight,
        target.calories = source.calories,
        target.price = source.price,
        target.description = source.description,
        target.photo_url = source.photo_url
    FROM dbo.MenuPositions AS target
    INNER JOIN (VALUES
        (N'Szynka 25cm Mrozona', N'Szynka 50cm Mrozona', 200, 400, CAST(40 AS DECIMAL(18, 0)), N'Hermetycznie zapakowana zapiekanka do odgrzania. Sklad: bagietka, maslo 20g, pieczarki 120g, cheddar 80g, mozzarella 40g, szynka 30g.', N'assets/images/zapMeatFrozen.png'),
        (N'Pieczarka 25cm Mrozona', N'Pieczarka 50cm Mrozona', 200, 400, CAST(40 AS DECIMAL(18, 0)), N'Hermetycznie zapakowana zapiekanka do odgrzania. Sklad: bagietka, maslo 20g, pieczarki 120g, cheddar 80g, mozzarella 40g.', N'assets/images/zapMushroomFrozen.png'),
        (N'Salame 25cm Mrozona', N'Salame 50cm Mrozona', 200, 200, CAST(36 AS DECIMAL(18, 0)), N'Hermetycznie zapakowana zapiekanka do odgrzania. Sklad: bagietka, maslo 20g, pieczarki 120g, cheddar 80g, mozzarella 40g, salame spianata 30g.', N'assets/images/zapSalameFrozen.png'),
        (N'Jalapeno Salame 25cm Mrozona', N'Jalapeno Salame 50cm Mrozona', 200, 200, CAST(36 AS DECIMAL(18, 0)), N'Hermetycznie zapakowana zapiekanka do odgrzania. Sklad: bagietka, maslo 20g, pieczarki 120g, cheddar 80g, mozzarella 40g, salame spianata 30g, jalapeno 20g, cebula czerwona 10g.', N'assets/images/zapJalapengoSalame.png'),
        (N'Serowa 25cm Mrozona', N'Serowa 50cm Mrozona', 200, 200, CAST(36 AS DECIMAL(18, 0)), N'Hermetycznie zapakowana zapiekanka do odgrzania. Sklad: bagietka, maslo 20g, pieczarki 120g, cheddar 80g, mozzarella 40g, ser plesniowy camembert 25g, ser plesniowy lazur 25g.', N'assets/images/zapCheeseFrozen.png')
    ) AS source(old_name, new_name, weight, calories, price, description, photo_url)
        ON target.name = source.old_name
    WHERE NOT EXISTS (
        SELECT 1
        FROM dbo.MenuPositions AS existing
        WHERE existing.name = source.new_name
    );
END;
GO

;WITH PositionSeed AS (
    SELECT
        seed.position_type,
        seed.name,
        seed.weight,
        seed.calories,
        seed.price,
        seed.description,
        seed.photo_url,
        seed.is_active
    FROM (VALUES
        (N'zapiekanki', N'Szynka 50cm', 200, 400, CAST(40 AS DECIMAL(18, 0)), N'bagietka, maslo 20g, pieczarki 120g, cheddar 80g, mozzarella 40g, szynka 30g', N'assets/images/zapMeat.png', CAST(1 AS BIT)),
        (N'zapiekanki', N'Pieczarka 50cm', 200, 400, CAST(40 AS DECIMAL(18, 0)), N'bagietka, maslo 20g, pieczarki 120g, cheddar 80g, mozzarella 40g', N'assets/images/zapMushroom.png', CAST(1 AS BIT)),
        (N'zapiekanki', N'Salame 50cm', 200, 200, CAST(36 AS DECIMAL(18, 0)), N'bagietka, maslo 20g, pieczarki 120g, cheddar 80g, mozzarella 40g, salame spianata 30g', N'assets/images/zapSalame.png', CAST(0 AS BIT)),
        (N'zapiekanki', N'Jalapeno Salame 50cm', 200, 200, CAST(36 AS DECIMAL(18, 0)), N'bagietka, maslo 20g, pieczarki 120g, cheddar 80g, mozzarella 40g, salame spianata 30g, jalapeno 20g, cebula czerwona 10g', N'assets/images/zapJalapengoSalame.png', CAST(0 AS BIT)),
        (N'zapiekanki', N'Serowa 50cm', 200, 200, CAST(36 AS DECIMAL(18, 0)), N'bagietka, maslo 20g, pieczarki 120g, cheddar 80g, mozzarella 40g, ser plesniowy camembert 25g, ser plesniowy lazur 25g', N'assets/images/zapCheese.png', CAST(1 AS BIT)),
        (N'zapiekanki', N'Goralska 50cm', 200, 200, CAST(36 AS DECIMAL(18, 0)), N'bagietka, maslo 20g, pieczarki 120g, cheddar 80g, mozzarella 40g, a''la oscypek 30g, zurawina 40g', N'assets/images/zapCheese.png', CAST(1 AS BIT)),
        (N'zapiekanki', N'Szarpana 50cm', 200, 200, CAST(36 AS DECIMAL(18, 0)), N'bagietka, maslo 20g, pieczarki 120g, cheddar 80g, mozzarella 40g, szarpane udko z rozna 140g', N'assets/images/zapMeat.png', CAST(0 AS BIT)),
        (N'zapiekanki', N'Rukola 50cm', 200, 200, CAST(36 AS DECIMAL(18, 0)), N'bagietka, maslo 20g, pieczarki 120g, cheddar 80g, mozzarella 40g, szynka dlugodojrzewajaca 30g, pomidorki koktajlowe 40g, rukola 10g', N'assets/images/zapMeat.png', CAST(0 AS BIT)),
        (N'kids', N'Kids Szynka 25cm', 100, 200, CAST(20 AS DECIMAL(18, 0)), N'Dziecieca wersja zapiekanki: bagietka, maslo 10g, pieczarki 60g, cheddar 40g, mozzarella 20g, szynka 15g', N'assets/images/zapMeat.png', CAST(1 AS BIT)),
        (N'kids', N'Kids Pieczarka 25cm', 100, 200, CAST(20 AS DECIMAL(18, 0)), N'Dziecieca wersja zapiekanki: bagietka, maslo 10g, pieczarki 60g, cheddar 40g, mozzarella 20g', N'assets/images/zapMushroom.png', CAST(1 AS BIT)),
        (N'kids', N'Kids Salame 25cm', 100, 100, CAST(18 AS DECIMAL(18, 0)), N'Dziecieca wersja zapiekanki: bagietka, maslo 10g, pieczarki 60g, cheddar 40g, mozzarella 20g, salame spianata 15g', N'assets/images/zapSalame.png', CAST(1 AS BIT)),
        (N'kids', N'Kids Jalapeno Salame 25cm', 100, 100, CAST(18 AS DECIMAL(18, 0)), N'Dziecieca wersja zapiekanki: bagietka, maslo 10g, pieczarki 60g, cheddar 40g, mozzarella 20g, salame spianata 15g, jalapeno 10g, cebula czerwona 5g', N'assets/images/zapJalapengoSalame.png', CAST(1 AS BIT)),
        (N'kids', N'Kids Serowa 25cm', 100, 100, CAST(18 AS DECIMAL(18, 0)), N'Dziecieca wersja zapiekanki: bagietka, maslo 10g, pieczarki 60g, cheddar 40g, mozzarella 20g, ser plesniowy camembert 12g, ser plesniowy lazur 12g', N'assets/images/zapCheese.png', CAST(1 AS BIT)),
        (N'zapiekanki_frozen', N'Szynka 50cm Mrozona', 200, 400, CAST(40 AS DECIMAL(18, 0)), N'Hermetycznie zapakowana zapiekanka do odgrzania. Sklad: bagietka, maslo 20g, pieczarki 120g, cheddar 80g, mozzarella 40g, szynka 30g.', N'assets/images/zapMeatFrozen.png', CAST(1 AS BIT)),
        (N'zapiekanki_frozen', N'Pieczarka 50cm Mrozona', 200, 400, CAST(40 AS DECIMAL(18, 0)), N'Hermetycznie zapakowana zapiekanka do odgrzania. Sklad: bagietka, maslo 20g, pieczarki 120g, cheddar 80g, mozzarella 40g.', N'assets/images/zapMushroomFrozen.png', CAST(1 AS BIT)),
        (N'zapiekanki_frozen', N'Salame 50cm Mrozona', 200, 200, CAST(36 AS DECIMAL(18, 0)), N'Hermetycznie zapakowana zapiekanka do odgrzania. Sklad: bagietka, maslo 20g, pieczarki 120g, cheddar 80g, mozzarella 40g, salame spianata 30g.', N'assets/images/zapSalameFrozen.png', CAST(1 AS BIT)),
        (N'zapiekanki_frozen', N'Jalapeno Salame 50cm Mrozona', 200, 200, CAST(36 AS DECIMAL(18, 0)), N'Hermetycznie zapakowana zapiekanka do odgrzania. Sklad: bagietka, maslo 20g, pieczarki 120g, cheddar 80g, mozzarella 40g, salame spianata 30g, jalapeno 20g, cebula czerwona 10g.', N'assets/images/zapJalapengoSalame.png', CAST(1 AS BIT)),
        (N'zapiekanki_frozen', N'Serowa 50cm Mrozona', 200, 200, CAST(36 AS DECIMAL(18, 0)), N'Hermetycznie zapakowana zapiekanka do odgrzania. Sklad: bagietka, maslo 20g, pieczarki 120g, cheddar 80g, mozzarella 40g, ser plesniowy camembert 25g, ser plesniowy lazur 25g.', N'assets/images/zapCheeseFrozen.png', CAST(1 AS BIT)),
        (N'udka', N'Udka z kurczaka (3 szt.)', 300, 600, CAST(20 AS DECIMAL(18, 0)), N'Pakiet 3 pieczonych udek z kurczaka. Kazda kolejna sztuka w koszyku dodaje kolejny pakiet 3 udek.', N'assets/images/chickenLeg.png', CAST(1 AS BIT)),
        (N'dodatki', N'Frytki', 150, 420, CAST(10 AS DECIMAL(18, 0)), N'Chrupiace frytki podawane na cieplo.', N'assets/images/fries.png', CAST(1 AS BIT)),
        (N'napoje', N'Coca Cola puszka 0.33', 330, 139, CAST(8 AS DECIMAL(18, 0)), N'Gazowany napoj Coca Cola w puszce 0.33 l.', NULL, CAST(1 AS BIT)),
        (N'napoje', N'Fanta puszka 0.33', 330, 144, CAST(8 AS DECIMAL(18, 0)), N'Gazowany napoj Fanta w puszce 0.33 l.', NULL, CAST(1 AS BIT)),
        (N'napoje', N'Sprite puszka 0.33', 330, 126, CAST(8 AS DECIMAL(18, 0)), N'Gazowany napoj Sprite w puszce 0.33 l.', NULL, CAST(1 AS BIT)),
        (N'lody', N'Lody smietankowe', 90, 180, CAST(10 AS DECIMAL(18, 0)), N'3 galki klasycznych lodow smietankowych.', N'assets/images/whiteIceCream.png', CAST(1 AS BIT)),
        (N'lody', N'Lody czekoladowe', 90, 190, CAST(10 AS DECIMAL(18, 0)), N'3 galki lodow czekoladowych.', N'assets/images/chocolateIceCream.png', CAST(1 AS BIT)),
        (N'lody', N'Lody truskawkowe', 90, 170, CAST(10 AS DECIMAL(18, 0)), N'3 galki lodow truskawkowych.', N'assets/images/strawberryIceCream.png', CAST(1 AS BIT))
    ) AS seed(position_type, name, weight, calories, price, description, photo_url, is_active)
)
MERGE dbo.MenuPositions AS target
USING PositionSeed AS source
    ON target.name = source.name
WHEN MATCHED THEN
    UPDATE SET
        position_type = source.position_type,
        weight = source.weight,
        calories = source.calories,
        price = source.price,
        description = source.description,
        photo_url = source.photo_url,
        is_active = source.is_active
WHEN NOT MATCHED THEN
    INSERT (
        position_type,
        name,
        weight,
        calories,
        price,
        description,
        photo_url,
        is_active
    )
    VALUES (
        source.position_type,
        source.name,
        source.weight,
        source.calories,
        source.price,
        source.description,
        source.photo_url,
        source.is_active
    );
GO
