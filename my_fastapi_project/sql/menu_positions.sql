IF OBJECT_ID(N'dbo.MenuPositions', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.MenuPositions (
        position_id INT IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_MenuPositions PRIMARY KEY,
        position_type NVARCHAR(50) NULL,
        sort_order INT NOT NULL
            CONSTRAINT DF_MenuPositions_sort_order DEFAULT (0),
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

IF COL_LENGTH(N'dbo.MenuPositions', N'sort_order') IS NULL
BEGIN
    ALTER TABLE dbo.MenuPositions
        ADD sort_order INT NOT NULL
            CONSTRAINT DF_MenuPositions_sort_order DEFAULT (0);
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
    UPDATE target
    SET target.sort_order = source.sort_order
    FROM dbo.MenuPositions AS target
    INNER JOIN (VALUES
        (10, N'Pieczarka 50cm'),
        (20, N'Szynka 50cm'),
        (30, N'Hawajska 50cm'),
        (40, N'Salami 50cm'),
        (40, N'Salame 50cm'),
        (50, N'Jalapeno salami 50cm'),
        (50, N'Jalapeno Salami 50cm'),
        (50, N'Jalapeno salame 50cm'),
        (50, N'Jalapeno Salame 50cm'),
        (60, N'Wiejska 50cm'),
        (70, N'Goralska 50cm'),
        (70, N'Góralska 50cm'),
        (80, N'Grecka 50cm')
    ) AS source(sort_order, name)
        ON LOWER(LTRIM(RTRIM(ISNULL(target.name, N'')))) =
           LOWER(LTRIM(RTRIM(source.name)))
    WHERE LOWER(ISNULL(target.position_type, N'')) LIKE N'%zapiek%';

    UPDATE dbo.MenuPositions
    SET is_active = 0
    WHERE name LIKE N'%25cm%'
      AND LOWER(ISNULL(position_type, N'')) NOT LIKE N'%kids%';

    UPDATE target
    SET
        target.name = source.new_name,
        target.sort_order = source.sort_order,
        target.weight = source.weight,
        target.calories = source.calories,
        target.price = source.price
    FROM dbo.MenuPositions AS target
    INNER JOIN (VALUES
        (N'Szynka 25cm', N'Szynka 50cm', 20, 200, 400, CAST(40 AS DECIMAL(18, 0))),
        (N'Pieczarka 25cm', N'Pieczarka 50cm', 10, 200, 400, CAST(40 AS DECIMAL(18, 0))),
        (N'Salame 25cm', N'Salame 50cm', 40, 200, 200, CAST(36 AS DECIMAL(18, 0))),
        (N'Jalapeno Salame 25cm', N'Jalapeno Salame 50cm', 50, 200, 200, CAST(36 AS DECIMAL(18, 0))),
        (N'Serowa 25cm', N'Serowa 50cm', 90, 200, 200, CAST(36 AS DECIMAL(18, 0)))
    ) AS source(old_name, new_name, sort_order, weight, calories, price)
        ON target.name = source.old_name
    WHERE NOT EXISTS (
        SELECT 1
        FROM dbo.MenuPositions AS existing
        WHERE existing.name = source.new_name
    );

    UPDATE target
    SET
        target.name = source.new_name,
        target.sort_order = source.sort_order,
        target.weight = source.weight,
        target.calories = source.calories,
        target.price = source.price,
        target.description = source.description,
        target.photo_url = source.photo_url
    FROM dbo.MenuPositions AS target
    INNER JOIN (VALUES
        (N'Szynka 25cm Mrozona', N'Szynka 50cm Mrozona', 20, 200, 400, CAST(40 AS DECIMAL(18, 0)), N'Hermetycznie zapakowana zapiekanka do odgrzania. Sklad: bagietka, maslo 20g, pieczarki 120g, cheddar 80g, mozzarella 40g, szynka 30g.', N'assets/images/zapMeatFrozen.png'),
        (N'Pieczarka 25cm Mrozona', N'Pieczarka 50cm Mrozona', 10, 200, 400, CAST(40 AS DECIMAL(18, 0)), N'Hermetycznie zapakowana zapiekanka do odgrzania. Sklad: bagietka, maslo 20g, pieczarki 120g, cheddar 80g, mozzarella 40g.', N'assets/images/zapMushroomFrozen.png'),
        (N'Salame 25cm Mrozona', N'Salame 50cm Mrozona', 40, 200, 200, CAST(36 AS DECIMAL(18, 0)), N'Hermetycznie zapakowana zapiekanka do odgrzania. Sklad: bagietka, maslo 20g, pieczarki 120g, cheddar 80g, mozzarella 40g, salame spianata 30g.', N'assets/images/zapSalameFrozen.png'),
        (N'Jalapeno Salame 25cm Mrozona', N'Jalapeno Salame 50cm Mrozona', 50, 200, 200, CAST(36 AS DECIMAL(18, 0)), N'Hermetycznie zapakowana zapiekanka do odgrzania. Sklad: bagietka, maslo 20g, pieczarki 120g, cheddar 80g, mozzarella 40g, salame spianata 30g, jalapeno 20g, cebula czerwona 10g.', N'assets/images/zapJalapengoSalame.png'),
        (N'Serowa 25cm Mrozona', N'Serowa 50cm Mrozona', 90, 200, 200, CAST(36 AS DECIMAL(18, 0)), N'Hermetycznie zapakowana zapiekanka do odgrzania. Sklad: bagietka, maslo 20g, pieczarki 120g, cheddar 80g, mozzarella 40g, ser plesniowy camembert 25g, ser plesniowy lazur 25g.', N'assets/images/zapCheeseFrozen.png')
    ) AS source(old_name, new_name, sort_order, weight, calories, price, description, photo_url)
        ON target.name = source.old_name
    WHERE NOT EXISTS (
        SELECT 1
        FROM dbo.MenuPositions AS existing
        WHERE existing.name = source.new_name
    );
END;
GO

UPDATE dbo.MenuPositions
SET description = REPLACE(
        description,
        N'a''la oscypek',
        N'ser wedzony a''la oscypek'
    )
WHERE LOWER(ISNULL(name, N'')) = N'goralska 50cm'
  AND description LIKE N'%a''la oscypek%';
GO

UPDATE dbo.MenuPositions
SET
    name = N'Udko z kurczaka - cala noga',
    weight = 300,
    calories = 600,
    price = CAST(20 AS DECIMAL(18, 0)),
    description = N'Jedna cala noga z kurczaka pieczona na chrupiaco. Kazda kolejna sztuka w koszyku dodaje kolejne udko.',
    photo_url = N'assets/images/chickenLeg.png',
    is_active = CAST(1 AS BIT)
WHERE LOWER(ISNULL(position_type, N'')) = N'udka';
GO

UPDATE dbo.MenuPositions
SET is_active = CAST(0 AS BIT)
WHERE LOWER(ISNULL(position_type, N'')) = N'zapiekanki_frozen';
GO

;WITH PositionSeed AS (
    SELECT
        seed.position_type,
        seed.sort_order,
        seed.name,
        seed.weight,
        seed.calories,
        seed.price,
        seed.description,
        seed.photo_url,
        seed.is_active
    FROM (VALUES
        (N'zapiekanki', 20, N'Szynka 50cm', 200, 400, CAST(40 AS DECIMAL(18, 0)), N'bagietka, maslo 20g, pieczarki 120g, cheddar 80g, mozzarella 40g, szynka 30g', N'assets/images/zapMeat.png', CAST(1 AS BIT)),
        (N'zapiekanki', 10, N'Pieczarka 50cm', 200, 400, CAST(40 AS DECIMAL(18, 0)), N'bagietka, maslo 20g, pieczarki 120g, cheddar 80g, mozzarella 40g', N'assets/images/zapMushroom.png', CAST(1 AS BIT)),
        (N'zapiekanki', 40, N'Salame 50cm', 200, 200, CAST(36 AS DECIMAL(18, 0)), N'bagietka, maslo 20g, pieczarki 120g, cheddar 80g, mozzarella 40g, salame spianata 30g', N'assets/images/zapSalame.png', CAST(0 AS BIT)),
        (N'zapiekanki', 50, N'Jalapeno Salame 50cm', 200, 200, CAST(36 AS DECIMAL(18, 0)), N'bagietka, maslo 20g, pieczarki 120g, cheddar 80g, mozzarella 40g, salame spianata 30g, jalapeno 20g, cebula czerwona 10g', N'assets/images/zapJalapengoSalame.png', CAST(0 AS BIT)),
        (N'zapiekanki', 90, N'Serowa 50cm', 200, 200, CAST(36 AS DECIMAL(18, 0)), N'bagietka, maslo 20g, pieczarki 120g, cheddar 80g, mozzarella 40g, ser plesniowy camembert 25g, ser plesniowy lazur 25g', N'assets/images/zapCheese.png', CAST(1 AS BIT)),
        (N'zapiekanki', 70, N'Goralska 50cm', 200, 200, CAST(36 AS DECIMAL(18, 0)), N'bagietka, maslo 20g, pieczarki 120g, cheddar 80g, mozzarella 40g, ser wedzony a''la oscypek 30g, zurawina 40g', N'assets/images/zapCheese.png', CAST(1 AS BIT)),
        (N'zapiekanki', 110, N'Szarpana 50cm', 200, 200, CAST(36 AS DECIMAL(18, 0)), N'bagietka, maslo 20g, pieczarki 120g, cheddar 80g, mozzarella 40g, szarpane udko z rozna 140g', N'assets/images/zapMeat.png', CAST(0 AS BIT)),
        (N'zapiekanki', 120, N'Rukola 50cm', 200, 200, CAST(36 AS DECIMAL(18, 0)), N'bagietka, maslo 20g, pieczarki 120g, cheddar 80g, mozzarella 40g, szynka dlugodojrzewajaca 30g, pomidorki koktajlowe 40g, rukola 10g', N'assets/images/zapMeat.png', CAST(0 AS BIT)),
        (N'kids', 10, N'Kids Szynka 25cm', 100, 200, CAST(20 AS DECIMAL(18, 0)), N'Dziecieca wersja zapiekanki: bagietka, maslo 10g, pieczarki 60g, cheddar 40g, mozzarella 20g, szynka 15g', N'assets/images/zapMeat.png', CAST(1 AS BIT)),
        (N'kids', 20, N'Kids Pieczarka 25cm', 100, 200, CAST(20 AS DECIMAL(18, 0)), N'Dziecieca wersja zapiekanki: bagietka, maslo 10g, pieczarki 60g, cheddar 40g, mozzarella 20g', N'assets/images/zapMushroom.png', CAST(1 AS BIT)),
        (N'kids', 30, N'Kids Salame 25cm', 100, 100, CAST(18 AS DECIMAL(18, 0)), N'Dziecieca wersja zapiekanki: bagietka, maslo 10g, pieczarki 60g, cheddar 40g, mozzarella 20g, salame spianata 15g', N'assets/images/zapSalame.png', CAST(1 AS BIT)),
        (N'kids', 40, N'Kids Jalapeno Salame 25cm', 100, 100, CAST(18 AS DECIMAL(18, 0)), N'Dziecieca wersja zapiekanki: bagietka, maslo 10g, pieczarki 60g, cheddar 40g, mozzarella 20g, salame spianata 15g, jalapeno 10g, cebula czerwona 5g', N'assets/images/zapJalapengoSalame.png', CAST(1 AS BIT)),
        (N'kids', 50, N'Kids Serowa 25cm', 100, 100, CAST(18 AS DECIMAL(18, 0)), N'Dziecieca wersja zapiekanki: bagietka, maslo 10g, pieczarki 60g, cheddar 40g, mozzarella 20g, ser plesniowy camembert 12g, ser plesniowy lazur 12g', N'assets/images/zapCheese.png', CAST(1 AS BIT)),
        (N'zapiekanki_frozen', 10, N'Pieczarka VAC', 200, 400, CAST(40 AS DECIMAL(18, 0)), N'Zapiekanka do wypieku w domu. Sklad: bagietka, maslo 20g, pieczarki 120g, cheddar 80g, mozzarella 40g. Sosy do VAC sa platne.', N'assets/images/zapMushroomFrozen.png', CAST(1 AS BIT)),
        (N'zapiekanki_frozen', 20, N'Salami VAC', 200, 200, CAST(36 AS DECIMAL(18, 0)), N'Zapiekanka do wypieku w domu. Sklad: bagietka, maslo 20g, pieczarki 120g, cheddar 80g, mozzarella 40g, salame spianata 30g. Sosy do VAC sa platne.', N'assets/images/zapSalameFrozen.png', CAST(1 AS BIT)),
        (N'zapiekanki_frozen', 30, N'Hawajska VAC', 200, 220, CAST(40 AS DECIMAL(18, 0)), N'Zapiekanka do wypieku w domu. Sklad: bagietka, maslo 20g, pieczarki 120g, cheddar 80g, mozzarella 40g, szynka 30g, ananas 40g. Sosy do VAC sa platne.', N'assets/images/zapMeatFrozen.png', CAST(1 AS BIT)),
        (N'zapiekanki_frozen', 40, N'Grecka VAC', 200, 220, CAST(40 AS DECIMAL(18, 0)), N'Zapiekanka do wypieku w domu. Sklad: bagietka, maslo 20g, pieczarki 120g, cheddar 80g, mozzarella 40g, oliwki 20g, pomidor 40g. Sosy do VAC sa platne.', N'assets/images/zapCheeseFrozen.png', CAST(1 AS BIT)),
        (N'udka', 10, N'Udko z kurczaka - cala noga', 300, 600, CAST(20 AS DECIMAL(18, 0)), N'Jedna cala noga z kurczaka pieczona na chrupiaco. Kazda kolejna sztuka w koszyku dodaje kolejne udko.', N'assets/images/chickenLeg.png', CAST(1 AS BIT)),
        (N'dodatki', 10, N'Frytki', 150, 420, CAST(10 AS DECIMAL(18, 0)), N'Chrupiace frytki podawane na cieplo.', N'assets/images/fries.png', CAST(1 AS BIT)),
        (N'napoje', 10, N'Coca Cola puszka 0.33', 330, 139, CAST(8 AS DECIMAL(18, 0)), N'Gazowany napoj Coca Cola w puszce 0.33 l.', NULL, CAST(1 AS BIT)),
        (N'napoje', 20, N'Fanta puszka 0.33', 330, 144, CAST(8 AS DECIMAL(18, 0)), N'Gazowany napoj Fanta w puszce 0.33 l.', NULL, CAST(1 AS BIT)),
        (N'napoje', 30, N'Sprite puszka 0.33', 330, 126, CAST(8 AS DECIMAL(18, 0)), N'Gazowany napoj Sprite w puszce 0.33 l.', NULL, CAST(1 AS BIT)),
        (N'lody', 10, N'Lody smietankowe', 90, 180, CAST(10 AS DECIMAL(18, 0)), N'3 galki klasycznych lodow smietankowych.', N'assets/images/whiteIceCream.png', CAST(1 AS BIT)),
        (N'lody', 20, N'Lody czekoladowe', 90, 190, CAST(10 AS DECIMAL(18, 0)), N'3 galki lodow czekoladowych.', N'assets/images/chocolateIceCream.png', CAST(1 AS BIT)),
        (N'lody', 30, N'Lody truskawkowe', 90, 170, CAST(10 AS DECIMAL(18, 0)), N'3 galki lodow truskawkowych.', N'assets/images/strawberryIceCream.png', CAST(1 AS BIT))
    ) AS seed(position_type, sort_order, name, weight, calories, price, description, photo_url, is_active)
)
MERGE dbo.MenuPositions AS target
USING PositionSeed AS source
    ON target.name = source.name
WHEN MATCHED THEN
    UPDATE SET
        position_type = source.position_type,
        sort_order = source.sort_order,
        weight = source.weight,
        calories = source.calories,
        price = source.price,
        description = source.description,
        photo_url = source.photo_url,
        is_active = source.is_active
WHEN NOT MATCHED THEN
    INSERT (
        position_type,
        sort_order,
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
        source.sort_order,
        source.name,
        source.weight,
        source.calories,
        source.price,
        source.description,
        source.photo_url,
        source.is_active
    );
GO
