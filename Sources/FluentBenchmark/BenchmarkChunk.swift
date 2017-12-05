import Async
import Service
import Dispatch
import Fluent
import Foundation

extension Benchmarker {
    /// The actual benchmark.
    fileprivate func _benchmark(on conn: Database.Connection) throws -> Future<Void> {
        var fetched64: [User<Database>] = []
        var fetched2047: [User<Database>] = []
        
        var future = Future<Void>(())
        
        for i in 1...512 {
            let user = User<Database>(name: "User \(i)", age: i)
            
            future = future.then {
                return user.save(on: conn)
            }
        }
        
        return future.then { () -> Future<Void> in
            return conn.query(User<Database>.self).chunk(max: 64) { chunk in
                if chunk.count != 64 {
                    self.fail("bad chunk count")
                }
                fetched64 += chunk
            }
        }.then { () -> Future<Void> in
            if fetched64.count != 512 {
                self.fail("did not fetch all - only \(fetched64.count) out of 2048")
            }
            
            return conn.query(User<Database>.self).chunk(max: 511) { chunk in
                if chunk.count != 511 && chunk.count != 1 {
                    self.fail("bad chunk count")
                }
                fetched2047 += chunk
            }
        }.map { _ in
            if fetched2047.count != 512 {
                self.fail("did not fetch all - only \(fetched2047.count) out of 2048")
            }
        }
    }

    /// Benchmark result chunking
    public func benchmarkChunking() throws -> Future<Void> {
        return pool.requestConnection().then { conn in
            return try self._benchmark(on: conn).map {
                self.pool.releaseConnection(conn)
            }
        }
    }
}

extension Benchmarker where Database.Connection: SchemaSupporting {
    /// Benchmark result chunking
    /// The schema will be prepared first.
    public func benchmarkChunking_withSchema() throws -> Future<Void> {
        return pool.requestConnection().then { conn -> Future<Database.Connection> in
            let promise = Promise<Database.Connection>()
            
            UserMigration<Database>.prepare(on: conn).do {
                promise.complete(conn)
            }.catch { _ in
                promise.complete(conn)
            }
            
            return promise.future
        }.then { conn -> Future<Void> in
            return try self._benchmark(on: conn).map {
                self.pool.releaseConnection(conn)
            }
        }
    }
}
