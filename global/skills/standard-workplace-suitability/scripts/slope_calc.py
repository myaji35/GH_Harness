import json, math
d=json.load(open("상권분석/파주법원리/data/san40_dem.json"))
pts=d["pts"]  # [lon,lat,elev]
step_lat=d["step_lat"]; step_lon=d["step_lon"]
# 격자 인덱싱
import collections
grid={}
lats=sorted(set(round(p[1],6) for p in pts))
lons=sorted(set(round(p[0],6) for p in pts))
for lo,la,e in pts: grid[(round(lo,6),round(la,6))]=e
# 각 점에서 인접(동·북) 이웃과 경사 계산
def near(v,arr):
    return min(arr,key=lambda a:abs(a-v))
cell_m_lat=step_lat*111000
cell_m_lon=step_lon*111000*math.cos(math.radians(sum(la for _,la,_ in pts)/len(pts)))
slopes=[]
for lo,la,e in pts:
    lo_r,la_r=round(lo,6),round(la,6)
    # 동쪽 이웃
    east=[(l,a) for (l,a) in grid if abs(a-la_r)<1e-5 and l>lo_r]
    north=[(l,a) for (l,a) in grid if abs(l-lo_r)<1e-5 and a>la_r]
    if east:
        ne=min(east,key=lambda p:p[0]); dz=abs(grid[ne]-e); slopes.append(math.degrees(math.atan2(dz,cell_m_lon)))
    if north:
        nn=min(north,key=lambda p:p[1]); dz=abs(grid[nn]-e); slopes.append(math.degrees(math.atan2(dz,cell_m_lat)))
slopes.sort()
import statistics
print(f"경사 샘플 수: {len(slopes)}")
print(f"평균 경사: {statistics.mean(slopes):.1f}°")
print(f"중앙값: {statistics.median(slopes):.1f}°  최대: {max(slopes):.1f}°")
# 경사 구간 분포
bins={"완경사(0-10°)":0,"보통(10-20°)":0,"급경사(20-30°)":0,"험준(30°+)":0}
for s in slopes:
    if s<10: bins["완경사(0-10°)"]+=1
    elif s<20: bins["보통(10-20°)"]+=1
    elif s<30: bins["급경사(20-30°)"]+=1
    else: bins["험준(30°+)"]+=1
print("\n=== 경사 구간 분포 ===")
for k,v in bins.items():
    print(f"  {k:16} {v:3d}개 ({v/len(slopes)*100:4.1f}%)")
# 개발가능성 판정 (산지관리법: 평균경사 25°이하 개발 유리, 그 이상 산지전용 제약)
avg=statistics.mean(slopes)
print(f"\n※ 산지전용 기준: 평균경사 {avg:.1f}° → ", "25°이하 전용가능권" if avg<=25 else "25°초과 전용제약 우려")
