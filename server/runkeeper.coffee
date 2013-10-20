'use strict'

async = require 'async'
logger = require './utils/logger'
passport = require 'passport'
request = require 'request'
string = require 'string'
_ = require 'underscore'
Firebase = require 'firebase'
RunKeeperStrategy = require('passport-runkeeper').Strategy
User = require '../client/scripts/models/user'

####################################################################################################

MAX_WORKOUTS_PROCESSED_AT_A_TIME = 20

RUNKEEPER_API_URL = 'https://api.runkeeper.com'
FIREBASE_URL = 'https://fitspector.firebaseIO.com'

####################################################################################################

requestCallback = (cb) ->
  (err, res, body) ->
    if not err and res.statusCode == 200
      cb null, body
    else
      cb err

####################################################################################################

runKeeper =
  api:
    accessToken:
      uri: 'https://runkeeper.com/apps/token'

    userInfo:
      path: '/user'
      accept: 'application/vnd.com.runkeeper.User+json'

    userActivities:
      path: '/fitnessActivities?pageSize=1000'
      accept: 'application/vnd.com.runkeeper.FitnessActivityFeed+json'

    profile:
      path: '/profile'
      accept: 'application/vnd.com.runkeeper.Profile+json'

  callbackURL: process.env.RUN_KEEPER_CALLBACK_URL ||
    throw new Error 'Missing RUN_KEEPER_CALLBACK_URL'
  clientId: process.env.RUN_KEEPER_ID || throw new Error 'Missing RUN_KEEPER_ID'
  secret: process.env.RUN_KEEPER_SECRET || throw new Error 'Missing RUN_KEEPER_SECRET'

  get: (accessToken, config, cb) ->
    opts =
      url: RUNKEEPER_API_URL + config.path
      json: {}
      headers:
        Authorization: 'Bearer ' + accessToken
        Accept: config.accept

    request.get opts, requestCallback cb

####################################################################################################

runKeeperWorkoutType = (type) ->
  switch type
    when "Running"
      "run"
    when "Cycling"
      "bik"
    when "Mountain Biking"
      "bik"
    when "Walking"
      "hik"
    when "Hiking"
      "hik"
    when "Downhill Skiing"
      "ski"
    when "Cross-Country Skiing"
      "xcs"
    when "Swimming"
      "swi"
    when "Rowing"
      "row"
    when "Elliptical", "Wheelchair", "Snowboarding", "Skating", "Other"
      "oth"
    else
      log.error "Unknown RunKeeper workout type", type
      "oth"

####################################################################################################

isRunKeeperId = (id) ->
  string(id).startsWith 'RKU'

####################################################################################################

addWorkout = (userRef, workouts, data, cb) ->
  prefix = "/fitnessActivities/"
  unless string(data.uri).startsWith(prefix)
    cb "Cannot get activity ID from its URI: " + data.uri
    return
  workoutId = "RKW" + string(data.uri).chompLeft(prefix).toString()

  # We already have this workout
  if workouts and workouts[workoutId]
    cb null, 0
    return

  workout =
    exerciseType: runKeeperWorkoutType(data.type)
    startTime: data["start_time"]
    totalDistance: data["total_distance"]
    totalDuration: data.duration

  # Note workout ID and save workout data.
  userRef.child("workouts").child(workoutId).set workout
  logger.info "Processed workout ", workoutId, " -> ", workout
  cb null, 1

####################################################################################################

loadAllWorkouts = (userId, accessToken) ->
  logger.info "Fetching all workouts for user: ", userId, " with token: ", accessToken
  userRef = new Firebase("https://fitspector.firebaseIO.com/users").child(userId)
  userRef.child("workouts").once "value", (workouts) ->
    runKeeper.get accessToken, runKeeper.api.userActivities, (err, response) ->
      logger.info 'Existing workouts: %s, RunKeeper error: %s, RunKeeper response: %s', workouts, err, response
      addWorkoutMap = _.partial(addWorkout, userRef, workouts.val())
      cb = (err, data) ->
        if err
          logger.error "Error while importing workouts for: ", userId, " -> ", err
        else
          total = _.reduce(data, ((x, y) -> x + y), 0)
          logger.info "Imported ", total, "new exercises for ", userId

      async.mapLimit response.items, MAX_WORKOUTS_PROCESSED_AT_A_TIME, addWorkoutMap, cb

####################################################################################################

createRunKeeperUser = (userId, token, done) ->
  logger.warn 'createRunKeeperUser | id: %d | token: %d', userId, token

  createUser = (err, profile) ->
    logger.warn 'createUser | %j', profile
    return done err if err
    return done 'Missing user profile' if not profile?
    user = User.fromRunKeeperProfile profile
    new Firebase("#{FIREBASE_URL}/users").child(userId).child('profile').update user
    logger.warn '  createdUser --> | %j', user
    done null, user

  runKeeper.get token, runKeeper.api.profile, createUser

####################################################################################################

loadRunKeeperUser = (userId, token, done) ->
  logger.warn 'loadRunKeeperUser | id: %d | token: %s', userId, token

  finishLoading = (err, res) ->
    # Invoke the callback
    done err, res
    # and then asynchronously load all user's workouts
    loadAllWorkouts userId, token if token? # provided we have the token

  loadUser = (userProfile) ->
    user = userProfile.val()
    logger.warn 'user read from DB: %j', user
    if user?
      finishLoading null, user
    else
      createRunKeeperUser userId, token, finishLoading

  noUser = ->
    logger.warn 'no user read from DB'
    createRunKeeperUser userId, token, finishLoading

  new Firebase("#{FIREBASE_URL}/users").child(userId).child('profile').once 'value', loadUser, noUser

####################################################################################################

module.exports =
  runKeeperStrategy: ->
    config =
      clientID: runKeeper.clientId
      clientSecret: runKeeper.secret
      callbackURL: runKeeper.callbackURL

    callback = (token, tokenSecret, profile, done) ->
      logger.warn 'RunKeeper callback | token: %d | tokenSecret: %d | profile: %j',
        token, tokenSecret, profile
      userId = 'RKU' + profile.id
      loadRunKeeperUser userId, token, done

    return new RunKeeperStrategy config, callback

  serializeUser: (user, done) ->
    done null, user.id

  deserializeUser: (id, done) ->
    switch
      when isRunKeeperId id then loadRunKeeperUser id, undefined, done
      else done "Unknown user ID: #{id}"
