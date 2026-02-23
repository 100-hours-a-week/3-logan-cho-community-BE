-- post_likes insert-centric workload for phase3 (C vs S)
-- Event flow per transaction:
-- 1) exists check (src path)
-- 2) insert ignore (src like path)

sysbench.cmdline.options = {
  case_id = {"schema case: C | S", "C"},
  sid_min = {"minimum source_id (inclusive)", 1},
  sid_max = {"maximum source_id (inclusive)", 1000},
  sid_step = {"source_id step per event", 1}
}

local drv
local con
local sid_cur
local sid_min
local sid_max
local sid_step
local sid_range
local case_id

local function next_sid()
  local sid = sid_cur
  sid_cur = sid_cur + sid_step
  if sid_cur > sid_max then
    sid_cur = sid_min + ((sid_cur - sid_min) % sid_range)
  end
  return sid
end

function thread_init()
  drv = sysbench.sql.driver()
  con = drv:connect()

  case_id = sysbench.opt.case_id
  sid_min = tonumber(sysbench.opt.sid_min)
  sid_max = tonumber(sysbench.opt.sid_max)
  sid_step = tonumber(sysbench.opt.sid_step)
  sid_range = sid_max - sid_min + 1

  -- Thread-local starting point to reduce collisions between threads.
  sid_cur = sid_min + ((sysbench.tid - 1) % sid_range)
end

function thread_done()
  con:disconnect()
end

function event()
  local sid = next_sid()

  con:query(string.format([[
SELECT 1
FROM post_likes_case pl
JOIN bench_likes_enriched b ON b.source_id = %d
WHERE pl.post_id = b.post_id
  AND pl.member_id = b.member_id
  AND pl.deleted_at IS NULL
LIMIT 1
]], sid))

  if case_id == "S" then
    con:query(string.format([[
INSERT IGNORE INTO post_likes_case (post_id, member_id, created_at, deleted_at)
SELECT post_id, member_id, created_at, NULL
FROM bench_likes_enriched
WHERE source_id = %d
]], sid))
  else
    con:query(string.format([[
INSERT IGNORE INTO post_likes_case (post_id, member_id, created_at, deleted_at)
SELECT post_id, member_id, created_at, NULL
FROM bench_likes_enriched
WHERE source_id = %d
]], sid))
  end
end
