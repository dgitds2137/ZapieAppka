from __future__ import annotations


_LOYALTY_PRICE_THRESHOLDS = (
    (8.99, 10),
    (11.99, 15),
    (14.99, 20),
    (17.99, 25),
    (20.99, 30),
    (23.99, 35),
    (26.99, 40),
    (29.99, 45),
)

_LOYALTY_ORDER_THRESHOLDS = (
    (30.0, 50),
    (50.0, 80),
    (70.0, 110),
    (90.0, 140),
)

LOYALTY_POINTS_PER_1_PLN = 10


def loyalty_points_for_price(price: float | int | None) -> int:
    if price is None:
        return 0

    normalized_price = float(price)
    if normalized_price <= 0:
        return 0

    for max_price, points in _LOYALTY_PRICE_THRESHOLDS:
        if normalized_price <= max_price:
            return points

    return 50


def loyalty_points_for_order_total(total_amount: float | int | None) -> int:
    if total_amount is None:
        return 0

    normalized_total = float(total_amount)
    if normalized_total <= 0:
        return 0

    for max_total, points in _LOYALTY_ORDER_THRESHOLDS:
        if normalized_total <= max_total:
            return points

    return 180
