#!/usr/bin/env python3
"""
genmaps.py - builds leveldata.asm (the map bank for the dungeon crawler).  v2

Bank layout (each map = 15 rows x 20 columns = 300 bytes):
    map 0         : level 1
    maps 1..24    : levels 2..9, three variants per level (random pick in-game)
    maps 25..49   : 25 maps for level 10 (walls + floor + exit only; the game
                    scatters monsters/items and swaps maps every 10 seconds)

Design rules enforced (and re-checked by check()):
  * NO single long winding road: dead ends are "braided" into loops, extra walls
    are knocked out, the shortest start->exit path is capped, and only a few
    cells on it are single points of failure.
  * You can dodge about half of the monsters, never all of them: the cheapest
    route to the exit meets at least a small FLOOR of monster weight (goblin = 1,
    dragon = 2; floor grows from 1 to 4 with the level) and at most HALF of the
    total weight.
  * Locked doors (L) guard VAULTS (dead-end pockets holding weapon / armor /
    potions). The exit is never locked. Keys (K) are always reachable without
    opening any door.
  * Every tile is reachable under the game's real key/door rules.
Run:  python genmaps.py   ->  writes leveldata.asm next to this file.
"""
import random, collections, heapq, os
W, H = 20, 15
DIRS = ((1, 0), (-1, 0), (0, 1), (0, -1))

# level: (braid%, extra loops, doors/vaults, goblins, dragons, potions, gold,
#         weapons, armor, (min,max) steps start->exit,
#         (unavoidable monster weight floor, max single-point-of-failure cells))
SPEC = {
 1: (0.90, 6, 0, 4, 0, 1, 5, 0, 0, (18, 32), (1, 2)),
 2: (0.85, 5, 1, 4, 1, 1, 5, 0, 0, (20, 34), (1, 2)),
 3: (0.80, 5, 1, 5, 1, 2, 5, 1, 0, (22, 36), (1, 2)),
 4: (0.75, 4, 2, 5, 2, 2, 5, 0, 1, (22, 38), (2, 2)),
 5: (0.70, 4, 2, 6, 2, 2, 5, 1, 0, (24, 40), (2, 2)),
 6: (0.65, 3, 3, 6, 3, 2, 5, 0, 1, (24, 40), (3, 3)),
 7: (0.60, 3, 3, 7, 3, 2, 5, 1, 0, (26, 42), (3, 3)),
 8: (0.55, 2, 4, 7, 4, 2, 5, 0, 1, (26, 44), (4, 3)),
 9: (0.50, 2, 4, 8, 4, 2, 5, 1, 0, (28, 46), (4, 3)),
}
POOL_RANGE = (20, 44)
POOL_MAX_CUT = 2     # level-10 pool maps: max single-point-of-failure cells

def carve(rng):
    g = [['#'] * W for _ in range(H)]
    g[1][1] = '.'
    st = [(1, 1)]
    while st:
        x, y = st[-1]
        nb = [(dx, dy) for dx, dy in ((0, -2), (0, 2), (-2, 0), (2, 0))
              if 1 <= x + dx <= 17 and 1 <= y + dy <= 13 and g[y + dy][x + dx] == '#']
        if not nb:
            st.pop(); continue
        dx, dy = rng.choice(nb)
        g[y + dy // 2][x + dx // 2] = '.'
        g[y + dy][x + dx] = '.'
        st.append((x + dx, y + dy))
    return g

CELLS = [(x, y) for y in range(1, 14, 2) for x in range(1, 18, 2)]

def braid(g, rng, pb):
    """turn dead ends into loops (probability pb each)"""
    cells = CELLS[:]; rng.shuffle(cells)
    for x, y in cells:
        if sum(g[y + dy][x + dx] != '#' for dx, dy in DIRS) == 1 and rng.random() < pb:
            cand = [(dx, dy) for dx, dy in DIRS if g[y + dy][x + dx] == '#'
                    and 1 <= x + 2 * dx <= 17 and 1 <= y + 2 * dy <= 13]
            if cand:
                dx, dy = rng.choice(cand); g[y + dy][x + dx] = '.'

def knock(g, rng, n):
    done = 0
    while done < n:
        x, y = rng.randint(1, 17), rng.randint(1, 13)
        if (x + y) % 2 == 1 and g[y][x] == '#':
            g[y][x] = '.'; done += 1

def bfs(g, start, blocked=('#',)):
    dist, par = {start: 0}, {start: None}
    q = collections.deque([start])
    while q:
        x, y = q.popleft()
        for dx, dy in DIRS:
            n = (x + dx, y + dy)
            if 0 <= n[0] < W and 0 <= n[1] < H and g[n[1]][n[0]] not in blocked and n not in dist:
                dist[n] = dist[(x, y)] + 1; par[n] = (x, y); q.append(n)
    return dist, par

def find(g, ch):
    return [(x, y) for y in range(H) for x in range(W) if g[y][x] == ch]

def cut_cells(g, E):
    """cells (not start/exit) whose removal disconnects the exit from the start"""
    dist, par = bfs(g, (1, 1))
    path, p = [], par[E]
    while p and p != (1, 1):
        path.append(p); p = par[p]
    cuts = 0
    for c in path:
        old = g[c[1]][c[0]]; g[c[1]][c[0]] = '#'
        d, _p = bfs(g, (1, 1))
        if E not in d: cuts += 1
        g[c[1]][c[0]] = old
    return cuts

def cut_list(g, E):
    """cells (not start/exit) that EVERY route from start to exit must cross"""
    dist, par = bfs(g, (1, 1))
    path, p = [], par[E]
    while p and p != (1, 1):
        path.append(p); p = par[p]
    out = []
    for c in path:
        old = g[c[1]][c[0]]; g[c[1]][c[0]] = '#'
        d, _p = bfs(g, (1, 1))
        if E not in d: out.append(c)
        g[c[1]][c[0]] = old
    return out

def route_min(g, kinds):
    """fewest monsters of the given kinds ('MD', 'M' or 'D') on any route to the
       exit (doors closed). This is what the player is GUARANTEED to meet."""
    best, pq = {(1, 1): 0}, [(0, (1, 1))]
    while pq:
        w, (x, y) = heapq.heappop(pq)
        if g[y][x] == 'E': return w
        if w > best[(x, y)]: continue
        for dx, dy in DIRS:
            n = (x + dx, y + dy); t = g[n[1]][n[0]]
            if t in '#L': continue
            nw = w + (1 if t in kinds else 0)
            if nw < best.get(n, 10 ** 9):
                best[n] = nw; heapq.heappush(pq, (nw, n))
    return 10 ** 9

def min_weight(g):
    """cheapest route to the exit in monster weight (goblin 1, dragon 2), doors closed"""
    best, pq = {(1, 1): 0}, [(0, (1, 1))]
    while pq:
        w, (x, y) = heapq.heappop(pq)
        if g[y][x] == 'E': return w
        if w > best[(x, y)]: continue
        for dx, dy in DIRS:
            n = (x + dx, y + dy); t = g[n[1]][n[0]]
            if t in '#L': continue
            nw = w + (1 if t == 'M' else 2 if t == 'D' else 0)
            if nw < best.get(n, 10 ** 9):
                best[n] = nw; heapq.heappush(pq, (nw, n))
    return 10 ** 9

def explore(g):
    """real game rules: K picks up a key, walking into L spends one.
       returns (exit reachable, set of every tile visited in some state)"""
    keys, doors = find(g, 'K'), find(g, 'L')
    kidx = {p: i for i, p in enumerate(keys)}
    didx = {p: i for i, p in enumerate(doors)}
    E = find(g, 'E')[0]
    start = ((1, 1), 0, 0)
    seen, q, tiles, reach = {start}, collections.deque([start]), {(1, 1)}, False
    while q:
        pos, km, dm = q.popleft()
        if pos == E: reach = True
        for dx, dy in DIRS:
            n = (pos[0] + dx, pos[1] + dy); t = g[n[1]][n[0]]
            if t == '#': continue
            nkm, ndm = km, dm
            if t == 'K': nkm |= 1 << kidx[n]
            if t == 'L' and not (dm >> didx[n]) & 1:
                if bin(km).count('1') - bin(dm).count('1') <= 0: continue
                ndm |= 1 << didx[n]
            s = (n, nkm, ndm)
            if s not in seen:
                seen.add(s); q.append(s); tiles.add(n)
    return reach, tiles

def build(spec, rng):
    pb, loops, nd, nm, ndr, npot, ngold, nw, na, (lo, hi), (floor_w, max_cut) = spec
    total_w = nm + 2 * ndr
    cap_w = total_w // 2
    for _ in range(20000):
        g = carve(rng); braid(g, rng, pb); knock(g, rng, loops)
        dist, par = bfs(g, (1, 1))
        Ec = [p for p in CELLS if lo <= dist.get(p, -1) <= hi]
        if not Ec: continue
        E = rng.choice(Ec)
        cuts_all = cut_list(g, E)
        if len(cuts_all) > max_cut: continue           # keep several routes
        cuts = [c for c in cuts_all if dist[c] >= 4]
        g[E[1]][E[0]] = 'E'
        # ---- vaults: dead-end cells behind a door on their single connector tile
        dead = []
        for (x, y) in CELLS:
            if (x, y) in ((1, 1), E): continue
            op = [(dx, dy) for dx, dy in DIRS if g[y + dy][x + dx] != '#']
            if len(op) == 1 and dist.get((x, y), 0) >= 8:
                dead.append(((x, y), (x + op[0][0], y + op[0][1])))
        if len(dead) < nd: continue
        vaults = rng.sample(dead, nd)
        for _c, z in vaults: g[z[1]][z[0]] = 'L'
        R, _p = bfs(g, (1, 1), ('#', 'L'))
        if len(R) < 40 or E not in R: continue
        D2, _p = bfs(g, (1, 1))
        base_used = {(1, 1), E} | {z for _c, z in vaults} | {c for c, _z in vaults}
        vault_items = ['W'] * nw + ['A'] * na
        left_p, left_g = npot, ngold
        while len(vault_items) < nd:
            if left_p > 0: vault_items.append('P'); left_p -= 1
            else: vault_items.append('$'); left_g -= 1
        vault_items = vault_items[:nd]
        if nd == 0: left_p, left_g = npot, ngold
        for _try in range(60):
            h = [row[:] for row in g]; used = set(base_used)
            def put(ch, cands):
                c = [p for p in cands if p not in used and h[p[1]][p[0]] == '.']
                if not c: return None
                p = rng.choice(c); h[p[1]][p[0]] = ch; used.add(p); return p
            ok = True
            for (c, _z), it in zip(vault_items and vaults, vault_items): h[c[1]][c[0]] = it
            # a small unavoidable fight: guards on chokepoints until the floor is met
            gl, dl, w, order = nm, ndr, 0, cuts[:]
            rng.shuffle(order)
            for c in order:
                if w >= floor_w: break
                if floor_w - w >= 2 and dl > 0 and w + 2 <= cap_w:
                    h[c[1]][c[0]] = 'D'; dl -= 1; w += 2
                elif gl > 0 and w + 1 <= cap_w:
                    h[c[1]][c[0]] = 'M'; gl -= 1; w += 1
                else: continue
                used.add(c)
            kp = [put('K', [p for p in R if R[p] >= 4]) for _k in range(nd)]
            ok &= all(kp)
            for i in range(dl):
                if i == 0 and nd and kp[0]:           # one dragon watches a key
                    near = [p for p in R if abs(p[0] - kp[0][0]) + abs(p[1] - kp[0][1]) <= 4 and R[p] >= 6]
                    got = put('D', near) or put('D', [p for p in R if R[p] >= 6])
                else:
                    got = put('D', [p for p in D2 if D2[p] >= 6 and p in R])
                ok &= bool(got)
            for _k in range(gl): ok &= bool(put('M', [p for p in D2 if D2[p] >= 6 and p in R]))
            for _k in range(left_p): ok &= bool(put('P', [p for p in D2 if D2[p] >= 5 and p in R]))
            for _k in range(left_g): ok &= bool(put('$', [p for p in D2 if D2[p] >= 3 and p in R]))
            if not ok: continue
            mw = min_weight(h)
            if mw > cap_w or mw < floor_w: continue
            reach, tiles = explore(h)
            floor = {(x, y) for y in range(H) for x in range(W) if h[y][x] != '#'}
            if reach and tiles >= floor:
                return h
    raise RuntimeError("no map found for spec %r" % (spec,))

def build_pool(rng):
    lo, hi = POOL_RANGE
    while True:
        g = carve(rng); braid(g, rng, rng.uniform(0.6, 0.95)); knock(g, rng, rng.randint(3, 8))
        dist, _p = bfs(g, (1, 1))
        Ec = [p for p in CELLS if lo <= dist.get(p, -1) <= hi]
        if not Ec: continue
        E = rng.choice(Ec)
        if cut_cells(g, E) > POOL_MAX_CUT: continue
        g[E[1]][E[0]] = 'E'
        return g

def check(rows, lvl):
    rows = [list(r) for r in rows]
    assert len(rows) == H and all(len(r) == W for r in rows), "size"
    assert all(rows[0][i] == rows[H-1][i] == '#' for i in range(W)) and all(r[0] == r[-1] == '#' for r in rows), "border"
    assert rows[1][1] == '.', "start"
    E = find(rows, 'E'); assert len(E) == 1, "exit"
    E = E[0]
    dist, _p = bfs(rows, (1, 1))
    lo, hi = SPEC[lvl][9] if lvl in SPEC else POOL_RANGE
    assert lo <= dist[E] <= hi, "route length %d" % dist[E]
    reach, tiles = explore(rows)
    floor = {(x, y) for y in range(H) for x in range(W) if rows[y][x] != '#'}
    assert reach and tiles >= floor, "unsolvable / unreachable tile"
    if lvl in SPEC:
        pb, loops, nd, nm, ndr, npot, ngold, nw, na, _r, (floor_w, max_cut) = SPEC[lvl]
        c = collections.Counter(ch for r in rows for ch in r)
        assert (c['L'], c['K'], c['M'], c['D'], c['P'], c['$'], c['W'], c['A']) == (nd, nd, nm, ndr, npot, ngold, nw, na), "counts"
        mw = min_weight(rows)
        assert floor_w <= mw <= (nm + 2 * ndr) // 2, "unavoidable fight weight %d out of range" % mw
        assert cut_cells(rows, E) <= max_cut, "too few alternative routes"
        Rd, _p = bfs(rows, (1, 1), ('#', 'L')); assert E in Rd, "exit is locked"
    else:
        assert cut_cells(rows, E) <= POOL_MAX_CUT, "pool map: too few alternative routes"

def main():
    rng = random.Random(20261108)
    maps, info = [], []
    for lvl in range(1, 10):
        for v in range(1 if lvl == 1 else 3):
            g = build(SPEC[lvl], rng)
            maps.append(g)
            d, _p = bfs(g, (1, 1)); E = find(g, 'E')[0]
            info.append("level %d%s (route %d steps, %d weak points, cheapest route meets weight %d of %d)" % (
                lvl, "" if lvl == 1 else " variant %d" % (v + 1), d[E], cut_cells(g, E),
                min_weight(g), SPEC[lvl][3] + 2 * SPEC[lvl][4]))
    for i in range(25):
        g = build_pool(rng); maps.append(g)
        d, _p = bfs(g, (1, 1)); E = find(g, 'E')[0]
        info.append("level 10 pool map %d (route %d steps, %d weak points)" % (i + 1, d[E], cut_cells(g, E)))
    assert len(maps) == 50
    for i, g in enumerate(maps):
        lvl = 1 if i == 0 else (2 + (i - 1) // 3 if i < 25 else 10)
        check([''.join(r) for r in g], lvl)
    out = ["; ============================================================",
           ";  leveldata.asm  -  map bank (GENERATED by genmaps.py - do not edit)",
           ";  50 maps x 300 bytes.  0 = level 1,  1..24 = levels 2-9 (3 variants",
           ";  each),  25..49 = the 25 maps used by level 10",
           ";  (included by main.asm - do NOT build this file on its own)",
           "; ============================================================",
           ".data", "mapBank LABEL BYTE"]
    for g, nfo in zip(maps, info):
        out.append("; ---- " + nfo)
        out += ['    BYTE "%s"' % ''.join(r) for r in g]
    open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "leveldata.asm"), "w").write("\n".join(out) + "\n")
    print("wrote leveldata.asm: %d maps, all verified" % len(maps))
    for s_ in info[:25]: print(" ", s_)

main()
