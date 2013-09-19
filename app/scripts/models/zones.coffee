'use strict'

root = exports ? this

class root.Zones
  constructor: (@zones, @Unit) ->

  @fromJson: (json, Unit) ->
    zones = _(json).map Unit.fromJson
    new Zones(zones, Unit)

  getTotal: ->
    _(@zones).reduce @Unit.plus, @Unit.zero
