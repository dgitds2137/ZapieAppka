IF OBJECT_ID(N'dbo.Users', N'U') IS NOT NULL
BEGIN
    MERGE dbo.Users AS target
    USING (
        VALUES
            (N'Klient Testowy 1', N'customer1@zapieapp.pl', N'500100100'),
            (N'Klient Testowy 2', N'customer2@zapieapp.pl', N'500200200'),
            (N'Klient Testowy 3', N'customer3@zapieapp.pl', N'500300300')
    ) AS seed(name, email, phone)
    ON LOWER(LTRIM(RTRIM(target.email))) = LOWER(seed.email)
    WHEN NOT MATCHED THEN
        INSERT (
            name,
            email,
            password,
            phone,
            role,
            loyalty_points,
            created_at
        )
        VALUES (
            seed.name,
            seed.email,
            N'$2b$12$LOor.5gOCwHR2LBfLI3yrehhfOAbgUUSslp.slwlITgI7uGnSgTAi',
            seed.phone,
            N'user',
            0,
            SYSUTCDATETIME()
        )
    WHEN MATCHED THEN
        UPDATE SET
            name = COALESCE(NULLIF(LTRIM(RTRIM(target.name)), N''), seed.name),
            phone = COALESCE(NULLIF(LTRIM(RTRIM(target.phone)), N''), seed.phone),
            role = N'user',
            loyalty_points = COALESCE(target.loyalty_points, 0);
END;
GO
