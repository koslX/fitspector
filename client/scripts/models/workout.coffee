'use strict'

root = exports ? this

class root.Workout
  constructor: (json, @id) ->
    @startTime = moment json.startTime
    # Normalize exerciseType id
    @exerciseType = json.exerciseType.toLowerCase()
    @notes = json.notes

    @totalCalories = json.totalCalories # TODO(koper) Create a type for calories
    @totalDistance = new Distance {meters: json.totalDistance}
    @totalDuration = new Time {seconds: json.totalDuration}
    @totalElevationGain = new Distance {meters: json.totalElevationGain}

    if not @totalDistance.isZero()
      @pace = new Pace
        time: @totalDuration,
        distance: @totalDistance

