logger = require '../utils/logger'
passport = require 'passport'
RunKeeperStrategy = require('passport-runkeeper').Strategy
string = require 'string'

isRunKeeperId = (id) ->
  string(id).startsWith 'RKU'

loadRunKeeperUser = (id) ->
  logger.warn "loadRunKeeperUser | id: %j", id
  # TODO(koper) Implement...
  null

createRunKeeperUser = (id, token) ->
  logger.warn "createRunKeeperUser | id: %j | token: %j", id, token
  user =
    id: 'RKU' + id
  user

module.exports =
  runKeeperStrategy: ->
    config =
      clientID: process.env.RUN_KEEPER_ID || throw new Error 'Missing RUN_KEEPER_ID'
      clientSecret: process.env.RUN_KEEPER_SECRET || throw new Error 'Missing RUN_KEEPER_SECRET'
      callbackURL: process.env.RUN_KEEPER_CALLBACK_URL || throw new Error 'Missing RUN_KEEPER_CALLBACK_URL'

    callback = (token, tokenSecret, profile, done) ->
      logger.warn "RunKeeper callback | token: %j | tokenSecret: %j | profile: %j", token, tokenSecret, profile
      user = loadRunKeeperUser profile.id
      user ?= createRunKeeperUser profile.id, token
      done null, user

    return new RunKeeperStrategy config, callback

  serializeUser: (user, done) ->
    done null, user.id

  deserializeUser: (id, done) ->
    user =
      switch
        when isRunKeeperId id then loadRunKeeperUser id
        else null
    done null, user
