using System;
using System.Linq;
using System.Net;
using System.Net.Sockets;
using System.Threading;
using MongoDB.Bson;
using MongoDB.Driver;
using Newtonsoft.Json;
using StackExchange.Redis;

namespace Worker
{
    public class Program
    {
        public static int Main(string[] args)
        {
            try
            {
                // Radius projects the recipe-generated connection string into
                // MONGO_URL. The fallback is the "db" service from docker-compose.
                var mongoUrl = Environment.GetEnvironmentVariable("MONGO_URL") ?? "mongodb://db:27017";
                var mongoDatabase = Environment.GetEnvironmentVariable("MONGO_DATABASE") ?? "votes";

                var votes = OpenMongoCollection(mongoUrl, mongoDatabase);
                var redisConn = OpenRedisConnection("redis");
                var redis = redisConn.GetDatabase();

                var definition = new { vote = "", voter_id = "" };
                while (true)
                {
                    // Slow down to prevent CPU spike, only query each 100ms
                    Thread.Sleep(100);

                    // Reconnect redis if down
                    if (redisConn == null || !redisConn.IsConnected) {
                        Console.WriteLine("Reconnecting Redis");
                        redisConn = OpenRedisConnection("redis");
                        redis = redisConn.GetDatabase();
                    }
                    string json = redis.ListLeftPopAsync("votes").Result;
                    if (json != null)
                    {
                        var vote = JsonConvert.DeserializeAnonymousType(json, definition);
                        Console.WriteLine($"Processing vote for '{vote.vote}' by '{vote.voter_id}'");
                        // The Mongo driver reconnects on its own, so a dropped
                        // connection surfaces here as a retryable write error.
                        UpdateVote(votes, vote.voter_id, vote.vote);
                    }
                }
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine(ex.ToString());
                return 1;
            }
        }

        private static IMongoCollection<BsonDocument> OpenMongoCollection(string connectionString, string databaseName)
        {
            var client = new MongoClient(connectionString);
            var collection = client.GetDatabase(databaseName).GetCollection<BsonDocument>("votes");

            while (true)
            {
                try
                {
                    // Force a round trip so startup waits for the database the
                    // same way the previous SQL implementation did.
                    client.GetDatabase(databaseName)
                        .RunCommand<BsonDocument>(new BsonDocument("ping", 1));
                    break;
                }
                catch (MongoException)
                {
                    Console.Error.WriteLine("Waiting for db");
                    Thread.Sleep(1000);
                }
                catch (TimeoutException)
                {
                    Console.Error.WriteLine("Waiting for db");
                    Thread.Sleep(1000);
                }
            }

            Console.Error.WriteLine("Connected to db");

            return collection;
        }

        private static ConnectionMultiplexer OpenRedisConnection(string hostname)
        {
            // Use IP address to workaround https://github.com/StackExchange/StackExchange.Redis/issues/410
            var ipAddress = GetIp(hostname);
            Console.WriteLine($"Found redis at {ipAddress}");

            while (true)
            {
                try
                {
                    Console.Error.WriteLine("Connecting to redis");
                    return ConnectionMultiplexer.Connect(ipAddress);
                }
                catch (RedisConnectionException)
                {
                    Console.Error.WriteLine("Waiting for redis");
                    Thread.Sleep(1000);
                }
            }
        }

        private static string GetIp(string hostname)
            => Dns.GetHostEntryAsync(hostname)
                .Result
                .AddressList
                .First(a => a.AddressFamily == AddressFamily.InterNetwork)
                .ToString();

        private static void UpdateVote(IMongoCollection<BsonDocument> votes, string voterId, string vote)
        {
            // One document per voter, so a repeat vote replaces the previous one.
            var filter = Builders<BsonDocument>.Filter.Eq("_id", voterId);
            var document = new BsonDocument { { "_id", voterId }, { "vote", vote } };

            votes.ReplaceOne(filter, document, new ReplaceOptions { IsUpsert = true });
        }
    }
}
