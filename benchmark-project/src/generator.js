const mysql = require('mysql2/promise');
const { MongoClient } = require('mongodb');
const config = require('./config');

const { POSTS_COUNT, BATCH_SIZE, TOTAL_USERS } = config.settings;

// 더미 데이터 생성 헬퍼
const generateDummyData = (count, startIndex) => {
    const data = [];
    for (let i = 0; i < count; i++) {
        const id = startIndex + i;
        data.push({
            authorId: Math.floor(Math.random() * TOTAL_USERS) + 1,
            title: `Title for post ${id} - Performance Test`,
            content: `Content body for post ${id}. This is a large text field to simulate real blog post content. `.repeat(10),
            views: Math.floor(Math.random() * 10000),
            likeCount: Math.floor(Math.random() * 1000),
            commentCount: 0,
            createdAt: new Date(),
            deletedAt: null
        });
    }
    return data;
};

async function generateMySQL() {
    console.log('🔵 Starting MySQL Data Generation...');
    const conn = await mysql.createConnection(config.mysqlConfig);

    // 1. 테이블 초기화
    await conn.query('SET FOREIGN_KEY_CHECKS = 0');
    await conn.query('DROP TABLE IF EXISTS comments');
    await conn.query('DROP TABLE IF EXISTS posts');

    // 테이블 생성 (인덱스는 나중에)
    await conn.query(`
        CREATE TABLE posts (
            id BIGINT AUTO_INCREMENT PRIMARY KEY,
            author_id BIGINT NOT NULL,
            title VARCHAR(255),
            content TEXT,
            views INT DEFAULT 0,
            like_count INT DEFAULT 0,
            comment_count INT DEFAULT 0,
            created_at DATETIME,
            deleted_at DATETIME NULL
        ) ENGINE=InnoDB
    `);
    console.log('   - MySQL Tables created.');

    // 2. 데이터 삽입 (Batch)
    let totalInserted = 0;
    while (totalInserted < POSTS_COUNT) {
        const currentBatch = Math.min(BATCH_SIZE, POSTS_COUNT - totalInserted);
        const data = generateDummyData(currentBatch, totalInserted);

        const values = data.map(d => [d.authorId, d.title, d.content, d.views, d.likeCount, d.commentCount, d.createdAt, d.deletedAt]);
        await conn.query('INSERT INTO posts (author_id, title, content, views, like_count, comment_count, created_at, deleted_at) VALUES ?', [values]);

        totalInserted += currentBatch;
        if(totalInserted % 50000 === 0) console.log(`   - MySQL: ${totalInserted} / ${POSTS_COUNT} inserted.`);
    }

    // 3. 인덱스 생성 (데이터 다 넣고 만드는게 훨씬 빠름)
    console.log('   - Creating MySQL Indexes (This may take a while)...');
    await conn.query('CREATE INDEX idx_created_at ON posts(created_at DESC)');
    await conn.query('CREATE INDEX idx_author_id ON posts(author_id)');
    await conn.query('SET FOREIGN_KEY_CHECKS = 1');

    console.log('MySQL Generation Complete.');
    await conn.end();
}

async function generateMongo() {
    console.log('Starting MongoDB Data Generation...');
    const client = new MongoClient(config.mongoConfig.url);
    await client.connect();
    const db = client.db(config.mongoConfig.dbName);
    const collection = db.collection('posts');

    // 1. 초기화
    await collection.drop().catch(() => {});

    // 2. 데이터 삽입 (Batch)
    let totalInserted = 0;
    while (totalInserted < POSTS_COUNT) {
        const currentBatch = Math.min(BATCH_SIZE, POSTS_COUNT - totalInserted);
        const data = generateDummyData(currentBatch, totalInserted);

        // Mongo는 _id 자동생성이지만, 비교를 위해 mysql id와 비슷하게 가려면 별도 처리 필요하지만
        // 여기선 Mongo Native 성능을 위해 자동 생성 ObjectId 사용 혹은 정수형 ID 부여
        // 공정 비교를 위해 authorId 등 필드는 동일하게 유지

        await collection.insertMany(data, { ordered: false });

        totalInserted += currentBatch;
        if(totalInserted % 50000 === 0) console.log(`   - MongoDB: ${totalInserted} / ${POSTS_COUNT} inserted.`);
    }

    // 3. 인덱스 생성
    console.log('   - Creating MongoDB Indexes...');
    await collection.createIndex({ createdAt: -1 });
    await collection.createIndex({ authorId: 1 });

    console.log('MongoDB Generation Complete.');
    await client.close();
}

async function run() {
    const start = Date.now();
    await Promise.all([generateMySQL(), generateMongo()]);
    console.log(`\n All Data Generated in ${(Date.now() - start) / 1000}s`);
    process.exit(0);
}

run();