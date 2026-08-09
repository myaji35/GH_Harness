#!/usr/bin/env python3
"""누리팜 작물 판정 — 셀당 공헌이익 / BEP 배수 산출

사용:
  python3 judge.py --name 상추 --cart 5.5 --weight 200 --price 12025 --cycle 30
  python3 judge.py --name 새싹삼 --flat 300 --tier 3 --weight 0 --unit-price 500 \
                   --var-cost 100 --cycle 45
  python3 judge.py --verify        # 2026-08-01 조사 결과로 검산
"""
import argparse

BEP_45 = 26_680      # 4·5동 한계원가 (셀감가 25,000 + 건축 1,680)
BEP_13 = 125_272     # 1~3동 (인건비 98,592 포함)


def cells_cylinder(cart_holes: float) -> float:
    """원통형: 카트리지 구수 × 32"""
    return cart_holes * 32


def cells_flat(density_per_m2: float, tiers: int) -> float:
    """평판형 1,000×1,000 × 단수"""
    return density_per_m2 * tiers


def monthly_revenue(plants, weight_g=0.0, price_per_kg=0.0,
                    unit_price=0.0, cycle_days=30):
    """무게 기준(kg단가) 또는 주당 기준(개당 단가) 중 하나"""
    turns = 30.0 / cycle_days
    if unit_price:                      # 새싹삼처럼 주당 판매
        return plants * unit_price * turns
    return plants * weight_g / 1000.0 * price_per_kg * turns


def judge(name, plants, revenue, var_cost_total=0.0, bep=BEP_45):
    margin = revenue - var_cost_total
    ratio = margin / bep
    verdict = "✅" if ratio >= 3 else ("⚠️ 조건부" if ratio >= 1 else "❌ BEP 미달")
    return {
        "name": name, "plants": plants, "revenue": revenue,
        "var_cost": var_cost_total, "margin": margin,
        "ratio": ratio, "verdict": verdict,
    }


def show(r):
    print(f"\n[{r['name']}]")
    print(f"  셀당 주수   : {r['plants']:,.0f}주")
    print(f"  셀당 월매출 : {r['revenue']:>10,.0f}원")
    if r["var_cost"]:
        print(f"  변동비      : {r['var_cost']:>10,.0f}원")
    print(f"  공헌이익    : {r['margin']:>10,.0f}원")
    print(f"  BEP 배수    : {r['ratio']:>10.2f}  {r['verdict']}")


# 2026-08-01 조사 실측 — 판정 함수 검산용
VERIFY = [
    # name, plants, weight_g, price_kg, cycle, var_rate, note
    ("상추류(5.5구)", cells_cylinder(5.5), 200, 12025, 30, 0.10, "청상추 경락 2kg특 ★"),
    ("루꼴라",        186,                  80, 36200, 30, 0.10, "경락 특등급 ★"),
    ("바질",          cells_cylinder(5.5),  60, 42670, 30, 0.10, "경락 특등급 ★"),
    ("고수(소포장)",   cells_cylinder(4.5),  60, 77000, 30, 0.10, "소포장 ★ 대포장은 10,375"),
    ("병풀",          cells_cylinder(4.5),  16.2, 150000, 30, 0.05, "⚠️ 생물단가·분말 미확정"),
    ("양상추(3구)",    cells_cylinder(3),   400,  1950, 45, 0.10, "❌ 초장·회전율"),
    ("깻잎(평판3단)",  16 * 3,               60, 15865, 30, 0.10, "❌ 낱장 수확"),
    ("고추(평판1단)",  8,                  3000/6, 5700, 30, 0.10, "❌ 8개월 점유"),
]


def run_verify():
    print("=" * 62)
    print(f"판정 함수 검산 — BEP {BEP_45:,}원 (4·5동 한계원가)")
    print("=" * 62)
    for n, p, w, pr, cy, vr, note in VERIFY:
        rev = monthly_revenue(p, weight_g=w, price_per_kg=pr, cycle_days=cy)
        r = judge(n, p, rev, rev * vr)
        show(r)
        print(f"  근거        : {note}")

    # 새싹삼은 주당 단가 방식
    p = cells_flat(300, 3)
    rev = monthly_revenue(p, unit_price=500, cycle_days=45)
    r = judge("새싹삼(평판3단)", p, rev, p * 100 * (30/45))
    show(r)
    print("  근거        : 묘삼 100원 매입 / 판매 500원 (대표 확인)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--name", default="작물")
    ap.add_argument("--cart", type=float, help="원통형 카트리지 구수(3~6)")
    ap.add_argument("--flat", type=float, help="평판형 재식밀도(주/㎡)")
    ap.add_argument("--tier", type=int, default=1, help="평판형 단수(1~3)")
    ap.add_argument("--weight", type=float, default=0.0, help="포기중량(g)")
    ap.add_argument("--price", type=float, default=0.0, help="kg 단가(원)")
    ap.add_argument("--unit-price", type=float, default=0.0, help="주당 판매가(원)")
    ap.add_argument("--var-cost", type=float, default=0.0, help="주당 변동비(원)")
    ap.add_argument("--var-rate", type=float, default=0.0, help="매출 대비 변동비율")
    ap.add_argument("--cycle", type=float, default=30, help="작기(일)")
    ap.add_argument("--span13", action="store_true", help="1~3동 BEP 적용")
    ap.add_argument("--verify", action="store_true")
    a = ap.parse_args()

    if a.verify:
        run_verify()
        return

    if a.cart:
        plants = cells_cylinder(a.cart)
    elif a.flat:
        plants = cells_flat(a.flat, a.tier)
    else:
        ap.error("--cart 또는 --flat 중 하나가 필요하다")

    rev = monthly_revenue(plants, a.weight, a.price, a.unit_price, a.cycle)
    var = a.var_cost * plants * (30/a.cycle) if a.var_cost else rev * a.var_rate
    show(judge(a.name, plants, rev, var, BEP_13 if a.span13 else BEP_45))


if __name__ == "__main__":
    main()
