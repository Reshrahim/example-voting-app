var express = require('express'),
    async = require('async'),
    { MongoClient } = require('mongodb'),
    cookieParser = require('cookie-parser'),
    app = express(),
    server = require('http').Server(app),
    io = require('socket.io')(server);

var port = process.env.PORT || 4000;

// Radius projects the recipe-generated connection string into MONGO_URL. The
// fallback is the "db" service from docker-compose, which runs without auth.
var mongoUrl = process.env.MONGO_URL || 'mongodb://db:27017';
var mongoDatabase = process.env.MONGO_DATABASE || 'votes';

io.on('connection', function (socket) {

  socket.emit('message', { text : 'Welcome!' });

  socket.on('subscribe', function (data) {
    socket.join(data.channel);
  });
});

var client = new MongoClient(mongoUrl);

async.retry(
  {times: 1000, interval: 1000},
  function(callback) {
    client.connect().then(
      function() { callback(null, client); },
      function(err) {
        console.error("Waiting for db");
        callback(err);
      }
    );
  },
  function(err, client) {
    if (err) {
      return console.error("Giving up");
    }
    console.log("Connected to db");
    getVotes(client.db(mongoDatabase).collection('votes'));
  }
);

function getVotes(collection) {
  collection.aggregate([{ $group: { _id: '$vote', count: { $sum: 1 } } }]).toArray().then(
    function(rows) {
      io.sockets.emit("scores", JSON.stringify(collectVotesFromResult(rows)));
    },
    function(err) {
      console.error("Error performing query: " + err);
    }
  ).then(function() {
    setTimeout(function() { getVotes(collection) }, 1000);
  });
}

function collectVotesFromResult(rows) {
  var votes = {a: 0, b: 0};

  rows.forEach(function (row) {
    votes[row._id] = row.count;
  });

  return votes;
}

app.use(cookieParser());
app.use(express.urlencoded());
app.use(express.static(__dirname + '/views'));

app.get('/', function (req, res) {
  res.sendFile(path.resolve(__dirname + '/views/index.html'));
});

server.listen(port, function () {
  var port = server.address().port;
  console.log('App running on port ' + port);
});
