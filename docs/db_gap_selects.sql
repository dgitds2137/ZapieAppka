-- Gap analysis: zapieapp (new) vs fastfoodapi (old)
-- Uruchom przez linked server albo podmień <OLD_DB>/<NEW_DB> na lokalne nazwy/ścieżki z db context.

-- 1) Tabele w starej i nowej bazie
SELECT name AS table_name, 'in_old_only' AS side
FROM fastfoodapi.dbo.sys.tables
EXCEPT
SELECT name, 'in_old_only'
FROM zapieapp.dbo.sys.tables

UNION ALL

SELECT name AS table_name, 'in_new_only' AS side
FROM zapieapp.dbo.sys.tables
EXCEPT
SELECT name, 'in_new_only'
FROM fastfoodapi.dbo.sys.tables;

-- 2) Liczba rekordów per tabela
SELECT 'Users' AS table_name, (SELECT COUNT(*) FROM fastfoodapi.dbo.Users) AS old_cnt, (SELECT COUNT(*) FROM zapieapp.dbo.Users) AS new_cnt
UNION ALL SELECT 'MenuPositions', (SELECT COUNT(*) FROM fastfoodapi.dbo.MenuPositions), (SELECT COUNT(*) FROM zapieapp.dbo.MenuPositions)
UNION ALL SELECT 'MenuAddons', (SELECT COUNT(*) FROM fastfoodapi.dbo.MenuAddons), (SELECT COUNT(*) FROM zapieapp.dbo.MenuAddons)
UNION ALL SELECT 'MenuPositionAddons', (SELECT COUNT(*) FROM fastfoodapi.dbo.MenuPositionAddons), (SELECT COUNT(*) FROM zapieapp.dbo.MenuPositionAddons)
UNION ALL SELECT 'ProductPrepTimeSettings', (SELECT COUNT(*) FROM fastfoodapi.dbo.ProductPrepTimeSettings), (SELECT COUNT(*) FROM zapieapp.dbo.ProductPrepTimeSettings)
UNION ALL SELECT 'AppRuntimeSettings', (SELECT COUNT(*) FROM fastfoodapi.dbo.AppRuntimeSettings), (SELECT COUNT(*) FROM zapieapp.dbo.AppRuntimeSettings)
UNION ALL SELECT 'Sessions', (SELECT COUNT(*) FROM fastfoodapi.dbo.Sessions), (SELECT COUNT(*) FROM zapieapp.dbo.Sessions)
UNION ALL SELECT 'UserAddresses', (SELECT COUNT(*) FROM fastfoodapi.dbo.UserAddresses), (SELECT COUNT(*) FROM zapieapp.dbo.UserAddresses)
UNION ALL SELECT 'CheckoutOrders', (SELECT COUNT(*) FROM fastfoodapi.dbo.CheckoutOrders), (SELECT COUNT(*) FROM zapieapp.dbo.CheckoutOrders)
UNION ALL SELECT 'CheckoutOrderItems', (SELECT COUNT(*) FROM fastfoodapi.dbo.CheckoutOrderItems), (SELECT COUNT(*) FROM zapieapp.dbo.CheckoutOrderItems)
UNION ALL SELECT 'CheckoutSupportAlerts', (SELECT COUNT(*) FROM fastfoodapi.dbo.CheckoutSupportAlerts), (SELECT COUNT(*) FROM zapieapp.dbo.CheckoutSupportAlerts)
UNION ALL SELECT 'CheckoutOrderMessages', (SELECT COUNT(*) FROM fastfoodapi.dbo.CheckoutOrderMessages), (SELECT COUNT(*) FROM zapieapp.dbo.CheckoutOrderMessages)
UNION ALL SELECT 'Orders', (SELECT COUNT(*) FROM fastfoodapi.dbo.Orders), (SELECT COUNT(*) FROM zapieapp.dbo.Orders)
UNION ALL SELECT 'OrderItems', (SELECT COUNT(*) FROM fastfoodapi.dbo.OrderItems), (SELECT COUNT(*) FROM zapieapp.dbo.OrderItems)
UNION ALL SELECT 'KitchenUpdates', (SELECT COUNT(*) FROM fastfoodapi.dbo.KitchenUpdates), (SELECT COUNT(*) FROM zapieapp.dbo.KitchenUpdates)
ORDER BY table_name;

-- 3) Braki rekordów: stare -> nowa (to, czego nie ma w zapieapp)
-- Users
SELECT o.email, o.name, o.phone, o.role, o.loyalty_points, o.created_at
FROM fastfoodapi.dbo.Users o
WHERE NOT EXISTS (SELECT 1 FROM zapieapp.dbo.Users n WHERE n.email = o.email);

-- MenuPositions (różnica po atrybutach biznesowych)
SELECT o.*
FROM (
  SELECT name, position_type, sort_order, weight, calories, CONVERT(decimal(10,2), price) AS price, description, photo_url, is_active
  FROM fastfoodapi.dbo.MenuPositions
) o
EXCEPT
SELECT name, position_type, sort_order, weight, calories, CONVERT(decimal(10,2), price) AS price, description, photo_url, is_active
FROM zapieapp.dbo.MenuPositions;

-- MenuAddons
SELECT o.*
FROM (
  SELECT name, description, CONVERT(decimal(10,2), price) AS price, photo_url, addon_group_key, sort_order, is_active
  FROM fastfoodapi.dbo.MenuAddons
) o
EXCEPT
SELECT name, description, CONVERT(decimal(10,2), price) AS price, photo_url, addon_group_key, sort_order, is_active
FROM zapieapp.dbo.MenuAddons;

-- MenuPositionAddons (po nazwach pozycji i dodatków)
SELECT p_old.name AS position_name, a_old.name AS addon_name, o.is_default, o.default_quantity
FROM fastfoodapi.dbo.MenuPositionAddons o
JOIN fastfoodapi.dbo.MenuPositions p_old ON p_old.position_id = o.position_id
JOIN fastfoodapi.dbo.MenuAddons a_old ON a_old.addon_id = o.addon_id
LEFT JOIN zapieapp.dbo.MenuPositionAddons n
  ON n.position_id = (SELECT TOP 1 p_new.position_id FROM zapieapp.dbo.MenuPositions p_new WHERE p_new.name = p_old.name)
 AND n.addon_id = (SELECT TOP 1 a_new.addon_id FROM zapieapp.dbo.MenuAddons a_new WHERE a_new.name = a_old.name)
 AND ISNULL(n.is_default, 0) = ISNULL(o.is_default, 0)
 AND ISNULL(n.default_quantity, 0) = ISNULL(o.default_quantity, 0)
WHERE n.menu_position_addon_id IS NULL
ORDER BY p_old.name, a_old.name;

-- ProductPrepTimeSettings
SELECT o.*
FROM (
  SELECT group_key, label, minutes, sort_order, is_active
  FROM fastfoodapi.dbo.ProductPrepTimeSettings
) o
EXCEPT
SELECT group_key, label, minutes, sort_order, is_active
FROM zapieapp.dbo.ProductPrepTimeSettings;

-- AppRuntimeSettings
SELECT o.*
FROM (
  SELECT setting_key, label, CONVERT(decimal(10,2), decimal_value) AS decimal_value, string_value, ISNULL(updated_by_user_id, -1) AS updated_by_user_id
  FROM fastfoodapi.dbo.AppRuntimeSettings
) o
EXCEPT
SELECT setting_key, label, CONVERT(decimal(10,2), decimal_value) AS decimal_value, string_value, ISNULL(updated_by_user_id, -1)
FROM zapieapp.dbo.AppRuntimeSettings;

-- Sessions (porównanie po session_token)
SELECT o.session_token, u.email AS user_email, o.created_at, o.last_seen_at
FROM fastfoodapi.dbo.Sessions o
JOIN fastfoodapi.dbo.Users u ON u.user_id = o.user_id
WHERE NOT EXISTS (SELECT 1 FROM zapieapp.dbo.Sessions n WHERE n.session_token = o.session_token);

-- UserAddresses (po użytkowniku + adresie)
SELECT u.email AS user_email, o.street, o.city, o.postal, o.phone, o.is_primary
FROM fastfoodapi.dbo.UserAddresses o
JOIN fastfoodapi.dbo.Users u ON u.user_id = o.user_id
WHERE NOT EXISTS (
  SELECT 1
  FROM zapieapp.dbo.UserAddresses n
  JOIN zapieapp.dbo.Users u2 ON u2.user_id = n.user_id
  WHERE u2.email = u.email
    AND ISNULL(n.street, '') = ISNULL(o.street, '')
    AND ISNULL(n.city, '') = ISNULL(o.city, '')
    AND ISNULL(n.postal, '') = ISNULL(o.postal, '')
    AND ISNULL(n.phone, '') = ISNULL(o.phone, '')
    AND ISNULL(n.is_primary, 0) = ISNULL(o.is_primary, 0)
);

-- CheckoutOrders (klucz biznesowy: verification_id)
SELECT o.verification_id, o.status, o.processing_status, o.payment_method, o.total_amount, o.client_created_at, o.created_at
FROM fastfoodapi.dbo.CheckoutOrders o
WHERE NOT EXISTS (SELECT 1 FROM zapieapp.dbo.CheckoutOrders n WHERE n.verification_id = o.verification_id);

-- CheckoutOrderItems (mapowane po verification_id zamówienia + cart_entry_id)
SELECT co_o.verification_id, oi_o.cart_entry_id, oi_o.position_id, oi_o.name, oi_o.quantity, CONVERT(decimal(10,2), oi_o.price) AS price
FROM fastfoodapi.dbo.CheckoutOrderItems oi_o
JOIN fastfoodapi.dbo.CheckoutOrders co_o ON co_o.checkout_order_id = oi_o.checkout_order_id
WHERE NOT EXISTS (
  SELECT 1
  FROM zapieapp.dbo.CheckoutOrderItems oi_n
  JOIN zapieapp.dbo.CheckoutOrders co_n ON co_n.checkout_order_id = oi_n.checkout_order_id
  WHERE co_n.verification_id = co_o.verification_id
    AND ISNULL(oi_n.cart_entry_id, -1) = ISNULL(oi_o.cart_entry_id, -1)
    AND ISNULL(oi_n.name, '') = ISNULL(oi_o.name, '')
    AND ISNULL(oi_n.quantity, 0) = ISNULL(oi_o.quantity, 0)
    AND CONVERT(decimal(10,2), ISNULL(oi_n.price, 0)) = CONVERT(decimal(10,2), ISNULL(oi_o.price, 0))
);

-- CheckoutSupportAlerts (mapowanie po verification_id)
SELECT co_o.verification_id, o.message, u_o.email AS user_email, o.created_at
FROM fastfoodapi.dbo.CheckoutSupportAlerts o
JOIN fastfoodapi.dbo.CheckoutOrders co_o ON co_o.checkout_order_id = o.checkout_order_id
LEFT JOIN fastfoodapi.dbo.Users u_o ON u_o.user_id = o.user_id
WHERE NOT EXISTS (
  SELECT 1
  FROM zapieapp.dbo.CheckoutSupportAlerts n
  JOIN zapieapp.dbo.CheckoutOrders co_n ON co_n.checkout_order_id = n.checkout_order_id
  WHERE co_n.verification_id = co_o.verification_id
    AND ISNULL(n.message, '') = ISNULL(o.message, '')
    AND ISNULL(CONVERT(varchar(30), n.created_at, 126), '') = ISNULL(CONVERT(varchar(30), o.created_at, 126), '')
);

-- CheckoutOrderMessages (mapowanie po verification_id + message)
SELECT co_o.verification_id, o.sender_role, o.author_label, o.message, o.staff_read_at, o.created_at
FROM fastfoodapi.dbo.CheckoutOrderMessages o
JOIN fastfoodapi.dbo.CheckoutOrders co_o ON co_o.checkout_order_id = o.checkout_order_id
WHERE NOT EXISTS (
  SELECT 1
  FROM zapieapp.dbo.CheckoutOrderMessages n
  JOIN zapieapp.dbo.CheckoutOrders co_n ON co_n.checkout_order_id = n.checkout_order_id
  WHERE co_n.verification_id = co_o.verification_id
    AND n.sender_role = o.sender_role
    AND n.author_label = o.author_label
    AND ISNULL(n.message, '') = ISNULL(o.message, '')
    AND ISNULL(CONVERT(varchar(30), n.created_at, 126), '') = ISNULL(CONVERT(varchar(30), o.created_at, 126), '')
);

-- 4) Co w nowej bazie nie ma w starej (odwrotna strona diffu)
-- (odpal analogicznie jak powyżej, zamieniając old <-> new)
-- przykład: Users
SELECT n.email, n.name, n.role
FROM zapieapp.dbo.Users n
WHERE NOT EXISTS (SELECT 1 FROM fastfoodapi.dbo.Users o WHERE o.email = n.email);
