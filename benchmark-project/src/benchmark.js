const mysql = require('mysql2/promise');
const { MongoClient } = require('mongodb');
const config = require('./config');

// 동시성 테스트를 위한 풀 사이즈 조정
const mysqlConfigOverride = {
    ...config.mysqlConfig,
    connectionLimit: 100
};

const { POSTS_COUNT, CONCURRENCY_TEST_USERS } = config.settings;

const SCENARIO = {
    FEED_USERS: 500,       // Test 1: 목록 조회 동시 접속자
    DEEP_USERS: 10,        // Test 2: 과거 조회 동시 접속자
    LIKE_USERS_MANY: 100,       // Test 3: 좋아요 동시 접속자 (여러 개시물)
    LIKE_USERS_ONE: 20,       // Test 3: 좋아요 동시 접속자 (단일 게시물)
    INSERT_USERS: 10,      // Test 4: 쓰기 동시 접속자
    DETAIL_USERS: 100,     // Test 5: 상세 조회 동시 접속자
    PAGE_SIZE: 20,
    MAX_PAGE_DEPTH: 10
};

// 통계 유틸리티
const calculateStats = (times) => {
    const min = Math.min(...times);
    const max = Math.max(...times);
    const avg = times.reduce((a, b) => a + b, 0) / times.length;
    return { min: min.toFixed(2), max: max.toFixed(2), avg: avg.toFixed(2) };
};

const getRandomInt = (min, max) => Math.floor(Math.random() * (max - min + 1)) + min;

async function runBenchmark() {
    console.log(`\n Starting Final Master Benchmark (Integrated Scenarios)`);
    console.log(`=======================================================`);

    const mysqlPool = mysql.createPool(mysqlConfigOverride);
    const mongoClient = new MongoClient(config.mongoConfig.url);
    await mongoClient.connect();
    const mongoDb = mongoClient.db(config.mongoConfig.dbName);
    const mongoCollection = mongoDb.collection('posts');

    const runTest = async (testName, testFn) => {
        const times = [];
        process.stdout.write(` [${testName}] Running: `);

        for (let i = 0; i < 10; i++) {
            global.gc && global.gc();
            const start = process.hrtime();
            await testFn(i);
            const diff = process.hrtime(start);
            times.push(diff[0] * 1000 + diff[1] / 1e6);
            process.stdout.write('.');
        }
        const stats = calculateStats(times);
        console.log(` Done!`);
        console.log(`   Avg: ${stats.avg}ms | Min: ${stats.min}ms | Max: ${stats.max}ms\n`);
        return stats;
    };

    try {
        // [Data Preparation] 모든 테스트에 필요한 데이터(커서, ID)를 사전에 한 번에 준비
        console.log(` Preparing Test Data (Caching Cursors & IDs)...`);

        const prepareData = async () => {
            // 1. [For Test 1] 목록 조회용 페이지별 커서
            const mysqlFeedCursors = [];
            const mongoFeedCursors = [];
            const limit = SCENARIO.PAGE_SIZE * SCENARIO.MAX_PAGE_DEPTH;

            const [mRows] = await mysqlPool.query(`SELECT created_at FROM posts ORDER BY created_at DESC LIMIT ${limit}`);
            const mgRows = await mongoCollection.find().project({ createdAt: 1 }).sort({ createdAt: -1 }).limit(limit).toArray();

            for(let p=1; p < SCENARIO.MAX_PAGE_DEPTH; p++) {
                const index = (p * SCENARIO.PAGE_SIZE) - 1;
                if (mRows[index]) mysqlFeedCursors.push(mRows[index].created_at);
                if (mgRows[index]) mongoFeedCursors.push(mgRows[index].createdAt);
            }

            // 2. [For Test 2] 과거 데이터 조회용 랜덤 커서 (Deep Cursor)
            const deepCursors = { mysql: [], mongo: [] };
            for(let i=0; i<50; i++) {
                const randomOffset = getRandomInt(100000, 900000);

                const [deepM] = await mysqlPool.query(`SELECT created_at FROM posts ORDER BY created_at DESC LIMIT 1 OFFSET ${randomOffset}`);
                if(deepM.length) deepCursors.mysql.push(deepM[0].created_at);

                const deepMg = await mongoCollection.find().project({ createdAt: 1 }).sort({ createdAt: -1 }).skip(randomOffset).limit(1).toArray();
                if(deepMg.length) deepCursors.mongo.push(deepMg[0].createdAt);
            }

            // 3. [For Test 5] 상세 조회용 최신글 100개 ID
            const [mIds] = await mysqlPool.query(`SELECT id FROM posts ORDER BY id DESC LIMIT 100`);
            const mgIds = await mongoCollection.find().project({ _id: 1 }).sort({ _id: -1 }).limit(100).toArray();

            return {
                mysqlFeedCursors, mongoFeedCursors,
                deepCursors,
                mysqlTargetIds: mIds.map(r => r.id),
                mongoTargetIds: mgIds.map(d => d._id)
            };
        };

        const PREPARED = await prepareData();
        console.log(` Data Prepared. Starting 5 Tests...\n`);


        // =================================================================
        // 1. [Read] 메인 피드 조회 (Projection: NO CONTENT)
        // 상황: 500명이 동시에 가벼운 목록 조회 (커서 기반)
        // =================================================================
        console.log(`1. Feed Load (Projection APPLIED, ${SCENARIO.FEED_USERS} users)`);

        await runTest('MySQL', async () => {
            const tasks = Array(SCENARIO.FEED_USERS).fill().map(() => {
                const targetPage = getRandomInt(1, SCENARIO.MAX_PAGE_DEPTH);
                const query = targetPage === 1
                    ? 'SELECT id, title, author_id, views, like_count, created_at FROM posts ORDER BY created_at DESC LIMIT 20'
                    : 'SELECT id, title, author_id, views, like_count, created_at FROM posts WHERE created_at < ? ORDER BY created_at DESC LIMIT 20';
                const params = targetPage === 1 ? [] : [PREPARED.mysqlFeedCursors[targetPage - 2]];
                return mysqlPool.query(query, params);
            });
            await Promise.all(tasks);
        });

        await runTest('MongoDB', async () => {
            const tasks = Array(SCENARIO.FEED_USERS).fill().map(() => {
                const targetPage = getRandomInt(1, SCENARIO.MAX_PAGE_DEPTH);
                const filter = targetPage === 1 ? {} : { createdAt: { $lt: PREPARED.mongoFeedCursors[targetPage - 2] } };
                return mongoCollection.find(filter)
                    .project({ _id: 1, title: 1, authorId: 1, views: 1, likeCount: 1, createdAt: 1 }) // Content 제외
                    .sort({ createdAt: -1 }).limit(20).toArray();
            });
            await Promise.all(tasks);
        });


        // =================================================================
        // 2. [Read] 과거 데이터 조회 (Deep Cursor Pre-fetched)
        // 상황: 10명이 과거 데이터를 조회 (커서 찾는 시간 제외, 순수 조회 시간)
        // =================================================================
        console.log(`2. Deep History Search (Pre-fetched Cursors, ${SCENARIO.DEEP_USERS} users)`);

        await runTest('MySQL', async () => {
            const tasks = Array(SCENARIO.DEEP_USERS).fill().map(() => {
                const cursor = PREPARED.deepCursors.mysql[getRandomInt(0, PREPARED.deepCursors.mysql.length - 1)];
                return mysqlPool.query('SELECT id, title, created_at FROM posts WHERE created_at < ? ORDER BY created_at DESC LIMIT 20', [cursor]);
            });
            await Promise.all(tasks);
        });

        await runTest('MongoDB', async () => {
            const tasks = Array(SCENARIO.DEEP_USERS).fill().map(() => {
                const cursor = PREPARED.deepCursors.mongo[getRandomInt(0, PREPARED.deepCursors.mongo.length - 1)];
                return mongoCollection.find({ createdAt: { $lt: cursor } })
                    .project({ _id: 1, title: 1, createdAt: 1 }) // Content 제외
                    .sort({ createdAt: -1 }).limit(20).toArray();
            });
            await Promise.all(tasks);
        });


        // =================================================================
        // 3.1 [Write] 좋아요 동시성
        // 상황: 100명이 동시에 좋아요 누름 (타겟 ID 랜덤)
        // =================================================================
        console.log(`3.1 Like Concurrency (Write, ${SCENARIO.LIKE_USERS_MANY} users)`);

        await runTest('MySQL', async () => {
            const tasks = Array(SCENARIO.LIKE_USERS_MANY).fill().map(() => {
                const targetId = PREPARED.mysqlTargetIds[getRandomInt(0, 99)]; // 미리 구해둔 유효한 ID 중 랜덤
                return mysqlPool.query('UPDATE posts SET like_count = like_count + 1 WHERE id = ?', [targetId]);
            });
            await Promise.all(tasks);
        });

        await runTest('MongoDB', async () => {
            const tasks = Array(SCENARIO.LIKE_USERS_MANY).fill().map(() => {
                const targetId = PREPARED.mongoTargetIds[getRandomInt(0, 99)]; // 미리 구해둔 유효한 ID 중 랜덤
                return mongoCollection.updateOne({ _id: targetId }, { $inc: { likeCount: 1 } });
            });
            await Promise.all(tasks);
        });

        // =================================================================
        // 3.2 [Write] 단일 게시물 좋아요 동시성
        // 상황: 인기글 하나에 20명이 동시에 좋아요를 누름 (Lock Contention 발생)
        // =================================================================
        console.log(`\n3.2 Like Concurrency (Write, ${SCENARIO.LIKE_USERS_ONE} users, SINGLE HOTSPOT)`);

        await runTest('MySQL', async () => {
            const tasks = Array(SCENARIO.LIKE_USERS_ONE).fill().map(() => {
                // 특정 게시물만 수행
                const targetId = PREPARED.mysqlTargetIds[0];
                return mysqlPool.query('UPDATE posts SET like_count = like_count + 1 WHERE id = ?', [targetId]);
            });
            await Promise.all(tasks);
        });

        await runTest('MongoDB', async () => {
            const tasks = Array(SCENARIO.LIKE_USERS_ONE).fill().map(() => {
                // 특정 게시물만 수행
                const targetId = PREPARED.mongoTargetIds[0];
                return mongoCollection.updateOne({ _id: targetId }, { $inc: { likeCount: 1 } });
            });
            await Promise.all(tasks);
        });


        // =================================================================
        // 4. [Write] 게시물 작성 (INSERT)
        // 상황: 10명이 동시에 글 작성
        // =================================================================
        console.log(`4. Post Insert (Write, ${SCENARIO.INSERT_USERS} users)`);

        await runTest('MySQL', async () => {
            const tasks = Array(SCENARIO.INSERT_USERS).fill().map(() =>
                mysqlPool.query('INSERT INTO posts (author_id, title, content, views, like_count, comment_count, created_at) VALUES (?, ?, ?, 0, 0, 0, ?)', [1, 'Title', 'Content Body...', new Date()])
            );
            await Promise.all(tasks);
        });

        await runTest('MongoDB', async () => {
            const tasks = Array(SCENARIO.INSERT_USERS).fill().map(() =>
                mongoCollection.insertOne({ authorId: 1, title: 'Title', content: 'Content Body...', views: 0, likeCount: 0, commentCount: 0, createdAt: new Date() })
            );
            await Promise.all(tasks);
        });


        // =================================================================
        // 5. [Read] 단일 게시물 상세 조회 (Full Fetch)
        // 상황: 500명이 상세 페이지 진입 (무거운 Content 포함, ID 기반)
        // =================================================================
        console.log(`5. Detail View (Full Fetch w/ Content, ${SCENARIO.DETAIL_USERS} users)`);

        await runTest('MySQL', async () => {
            const tasks = Array(SCENARIO.DETAIL_USERS).fill().map(() => {
                const targetId = PREPARED.mysqlTargetIds[getRandomInt(0, 99)];
                return mysqlPool.query('SELECT * FROM posts WHERE id = ?', [targetId]);
            });
            await Promise.all(tasks);
        });

        await runTest('MongoDB', async () => {
            const tasks = Array(SCENARIO.DETAIL_USERS).fill().map(() => {
                const targetId = PREPARED.mongoTargetIds[getRandomInt(0, 99)];
                return mongoCollection.findOne({ _id: targetId });
            });
            await Promise.all(tasks);
        });

    } catch (e) {
        console.error("Benchmark Error:", e);
    } finally {
        await mysqlPool.end();
        await mongoClient.close();
    }
}

runBenchmark();