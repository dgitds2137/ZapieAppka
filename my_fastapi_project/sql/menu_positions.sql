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

;WITH PositionSeed AS (
    SELECT
        seed.position_type,
        seed.name,
        seed.weight,
        seed.calories,
        seed.price,
        seed.description,
        seed.photo_url
    FROM (VALUES
        (N'zapiekanki', N'Szynka 25cm', 100, 200, CAST(20 AS DECIMAL(18, 0)), N'bagietka, maslo 10g, pieczarki 60g, cheddar 40g, mozzarella 20g, szynka 15g', N'https://restaumatic-production.imgix.net/uploads/accounts/304057/media_library/3b2b6633-9a7b-4ba3-aff4-a51a5ef320ef.jpg?auto=compress%2Cformat&blur=0&crop=focalpoint&fit=max&fp-x=0.5&fp-y=0.5&h=auto&rect=0%2C0%2C2000%2C1333&w=1920'),
        (N'zapiekanki', N'Pieczarka 25cm', 100, 200, CAST(20 AS DECIMAL(18, 0)), N'bagietka, maslo 10g, pieczarki 60g, cheddar 40g, mozzarella 20g', N'https://restaumatic-production.imgix.net/uploads/accounts/304057/media_library/ae8dd6c5-c026-4669-b918-285c0e138ba5.jpg?auto=compress%2Cformat&blur=0&crop=focalpoint&fit=max&fp-x=0.5&fp-y=0.5&h=auto&rect=0%2C0%2C2000%2C1333&w=1920'),
        (N'zapiekanki', N'Salame 25cm', 100, 100, CAST(18 AS DECIMAL(18, 0)), N'bagietka, maslo 10g, pieczarki 60g, cheddar 40g, mozzarella 20g, salame spianata 15g', N'https://restaumatic-production.imgix.net/uploads/accounts/304057/media_library/03f058b5-5184-4ce7-80ae-52f502b3acac.jpg?auto=compress%2Cformat&blur=0&crop=focalpoint&fit=max&fp-x=0.5&fp-y=0.5&h=auto&rect=0%2C0%2C2000%2C1333&w=1920'),
        (N'zapiekanki', N'Jalapeno Salame 25cm', 100, 100, CAST(18 AS DECIMAL(18, 0)), N'bagietka, maslo 10g, pieczarki 60g, cheddar 40g, mozzarella 20g, salame spianata 15g, jalapeno 10g, cebula czerwona 5g', N'https://restaumatic-production.imgix.net/uploads/accounts/304057/media_library/e20874a6-4dc0-4156-82f2-ccd41e326c67.jpg?auto=compress%2Cformat&blur=0&crop=focalpoint&fit=max&fp-x=0.5&fp-y=0.5&h=auto&rect=0%2C0%2C2000%2C1333&w=1920'),
        (N'zapiekanki', N'Serowa 25cm', 100, 100, CAST(18 AS DECIMAL(18, 0)), N'bagietka, maslo 10g, pieczarki 60g, cheddar 40g, mozzarella 20g, ser plesniowy camembert 12g, ser plesniowy lazur 12g', N'https://restaumatic-production.imgix.net/uploads/accounts/304057/media_library/6d147b4e-7608-4241-975b-25db4f34917a.jpg?auto=compress%2Cformat&blur=0&crop=focalpoint&fit=max&fp-x=0.5&fp-y=0.5&h=auto&rect=0%2C0%2C2000%2C1333&w=1920'),
        (N'dodatki', N'Frytki', 150, 420, CAST(10 AS DECIMAL(18, 0)), N'Chrupiace frytki podawane na cieplo.', N'assets/images/fries.png'),
        (N'napoje', N'Coca Cola puszka 0.33', 330, 139, CAST(8 AS DECIMAL(18, 0)), N'Gazowany napoj Coca Cola w puszce 0.33 l.', NULL),
        (N'napoje', N'Fanta puszka 0.33', 330, 144, CAST(8 AS DECIMAL(18, 0)), N'Gazowany napoj Fanta w puszce 0.33 l.', NULL),
        (N'napoje', N'Sprite puszka 0.33', 330, 126, CAST(8 AS DECIMAL(18, 0)), N'Gazowany napoj Sprite w puszce 0.33 l.', NULL),
        (N'lody', N'Lody smietankowe', 90, 180, CAST(10 AS DECIMAL(18, 0)), N'Porcja klasycznych lodow smietankowych.', N'assets/images/whiteIceCream.png'),
        (N'lody', N'Lody czekoladowe', 90, 190, CAST(10 AS DECIMAL(18, 0)), N'Porcja lodow czekoladowych.', N'assets/images/chocolateIceCream.png'),
        (N'lody', N'Lody truskawkowe', 90, 170, CAST(10 AS DECIMAL(18, 0)), N'Porcja lodow truskawkowych.', N'assets/images/strawberryIceCream.png')
    ) AS seed(position_type, name, weight, calories, price, description, photo_url)
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
        photo_url = source.photo_url
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
        1
    );
GO
