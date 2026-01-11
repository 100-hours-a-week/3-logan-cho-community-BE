module.exports = {
    mysqlConfig: {
        host: 'mysql', // docker-compose service name
        user: 'root',
        password: 'rootpassword',
        database: 'benchmark_db',
        waitForConnections: true,
        connectionLimit: 10,
        queueLimit: 0
    },
    mongoConfig: {
        url: 'mongodb://mongo:27017',
        dbName: 'benchmark_db'
    },
    // 테스트 규모 설정
    settings: {
        POSTS_COUNT: 1000000,    // 100만 건
        BATCH_SIZE: 5000,        // 한번에 삽입할 개수
        TOTAL_USERS: 10000,
        CONCURRENCY_TEST_USERS: 100 // 동시성 테스트 유저 수
    }
};