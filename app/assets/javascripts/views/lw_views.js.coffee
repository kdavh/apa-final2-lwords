LW.Views.MenuBar = Backbone.View.extend
  initialize: (options) -> 
    @$openMenuButton = @$('#menu-button')
    @$menu = @$('#menu')
    @$body = $('body')

    @timerView = new LW.Views.Timer({el: @$('#timer')})
    @scoreView = new LW.Views.Score
      model: new LW.Models.Score()
      el: @$('#score-display')

    # events, can't use backbone notation because of variables
    @$el.on touchType, '#menu-button',  @openMenu.bind(this)
    @$el.on touchType, '#new-game-button', @startMatch.bind(this)
    @$('#change-lang-button').on touchType, @promptToChangeLang.bind(this)
    @$('#help-button').on 'click', @showHelp
  openMenu: (event) ->
    @$menu.removeClass('hidden')
    @$body.on touchType + '.menu-close', (event) =>
      @closeMenu(event)

    event.stopPropagation()

  closeMenu: (event) ->
    @$menu.addClass('hidden')
    @$body.off touchType + '.menu-close'

    event.stopPropagation()

  showHelp: (event) ->
    LW.gameBoard.$('#help-display').fadeIn()

  hideHelp: (event) ->
    LW.gameBoard.$('#help-display').fadeOut()

  startMatch: ->
    # logic
    LW.gameBoard.getDictionary()

    LW.gameBoard.cleanUpListeners()
    LW.gameBoard.model.saveAndResetMatch()
    LW.gameBoard.model.emptyForRound()
    LW.gameBoard.model.prepNewMatch()

    #logic and ui
    @timerView.stop()
    @timerView.start()

    # ui
    LW.gameBoard.hideEndRoundDisplay()
    LW.gameBoard.emptyForRound()
    LW.gameBoard.populatePickLetters()
    LW.gameBoard.startListening()

  promptToChangeLang: ->
    @showLanguageChoicesDisplay()


LW.Views.GameBoard = Backbone.View.extend
  initialize: (options) ->
    @$el = $('#game-board')
    @initJquerySelectors()

    @endRoundView = new LW.Views.EndRound
      model: @model.get('match')
      el: @$endRoundDisplay

    @$('#help-display').on 'click', LW.menuBar.hideHelp.bind(LW.menuBar)
  events:

    'click #end-round-display' : 'startNewRound'

  initJquerySelectors: ->
    @$loadingGif = @$('#loading-gif')
    @$endRoundDisplay = @$('#end-round-display')
    @$guessWordBarText = @$('#guess-word-bar-text')
    @$pickLettersBar = @$('#pick-letters-bar')
    @$definitionBarText = @$('#definition-bar-text')
    @$foundWordsBarText = @$('#found-words-bar-text')
    @$deleteKey = @$('#delete-key')
    @$enterKey = @$('#enter-key')
    # @$letterSquares defined later

  startNewRound: ->
    # logic
    @model.emptyForRound()
    @model.prepNewRound()
    @cleanUpListeners()

    #logic and ui
    LW.menuBar.timerView.stop()
    LW.menuBar.timerView.start()

    #view
    @hideEndRoundDisplay()
    @emptyForRound()
    @populatePickLetters()
    @startListening()

  emptyForRound: ->
    @$('#pick-letters-bar').empty()
    @$guessWordBarText.empty()
    @$('#definition-bar-text').empty()
    @$foundWordsBarText.empty()

  getDictionary: ->
    @fetchNewDictionary() unless LW.dictionary[@model.currentLanguage]    

  fetchNewDictionary: ->
    @$loadingGif.show()
    LW.dictionary[@model.currentLanguage] = new LW.Models.Dictionary
      language: @model.currentLanguage

    LW.dictionary[@model.currentLanguage].fetch
      success: (model, response, options) =>
        @$loadingGif.hide()

  populatePickLetters: ->
    lettersBar = @$('#pick-letters-bar')
    _.each @model.get('currentLetters'), (ltr, i) =>
      lettersBar.append(
        "<div class='letter-square' data-pos='#{i}' data-ltr='#{ltr}'>" +
        ltr + '</div>'
      )

  cleanUpListeners: ->
    @$('.letter-square').off 'click.game'
    @$deleteKey.off 'click.game'
    @$enterKey.off 'click.game'
    $(document).off 'keydown.game'

  startListening: ->
    @$letterSquares = @$('.letter-square')

    @addLetterSquaresClickListeners()
    @addDeleteClickListener()
    @addEnterClickListener()
    @addKeyboardListeners()
    @addClickForDefinitionListeners()

  addLetterSquaresClickListeners: ->
    @$letterSquares.on touchType + '.game', (event) =>
      $target = $(event.currentTarget)
      pos = $target.attr('data-pos')

      # if letter hasn't been clicked, add it to view
      # and add to game model's records
      if @model.get('pickedLettersMask')[pos] == false
        ltr = $target.attr('data-ltr')

        # onto model
        @model.get('pickedLettersMask')[pos] = ltr
        @model.get('formedWordArray').push(ltr)

        # onto view
        $target.addClass('picked')
        @$guessWordBarText.append(ltr)

  addDeleteClickListener: ->
    @$deleteKey.on touchType + '.game', (event) =>
      if @model.get('formedWordArray').length 

        # off of model
        ltr = @model.get('formedWordArray').pop()
        removedLetterPos = @model.get('pickedLettersMask').indexOf( ltr )
        @model.get('pickedLettersMask')[removedLetterPos] = false

        # off of view
        @$letterSquares
          .filter('[data-pos="' + removedLetterPos + '"]')
          .removeClass('picked')
        @$guessWordBarText.html( @$guessWordBarText.html().slice(0, -1) )

  addEnterClickListener: ->
    @$enterKey.on touchType + '.game', (event) =>
      # onto logic
      @model.resetWordPick()
      # get word, and reset view
      word = @getAndResetWordPick()
      # on view
      @resetPickLettersBar()

      if @model.inDictionaryAndNotAlreadyChosen( word )
        # onto logic
        @model.addToFoundWords( word )
        # onto view
        @displayFound(word)

    # TEMPORARY: need to make all click listeners just call a function
    # so that the keyboard listeners, etc can call that function

  addKeyboardListeners: ->
    $(document).on 'keydown.game', =>
      key = event.which

      switch key
        when 13
          @$enterKey.trigger touchType
        when 8
          @$deleteKey.trigger touchType
          event.preventDefault()
        else
          @pickLetterAndTriggerClick( key )

  addClickForDefinitionListeners: ->
    @$foundWordsBarText.on touchType, '.word', =>
      word = $(event.target).html()
      @lookUpAndDisplay(word)

  lookUpAndDisplay: (word) ->
    LW.dictionary[@model.currentLanguage].lookUp(word)

  hideEndRoundDisplay: ->
    @$endRoundDisplay.fadeOut()

  pickLetterAndTriggerClick: (key) ->
    if key >= 65 && key <= 90
      ltr = String.fromCharCode(key).toLowerCase()
      @$letterSquares
        .filter($('[data-ltr="' + ltr + '"]:not(.picked)'))
        .first()
        .trigger(touchType)

  getAndResetWordPick: ->
    word = @$guessWordBarText.html()
    @$guessWordBarText.empty()
    word

  resetPickLettersBar: ->
    @$letterSquares.removeClass('picked')

  displayFound: (word) ->
    @$('#found-word-display')
      .html(word).show().fadeOut(3000)
    wordEl = $("<span class='word'>" + word + "</span>")
    @$foundWordsBarText.append(wordEl)
    # display translation
    @lookUpAndDisplay(word)

  endRound: ->
    @model.recordTotals()
    @openEndRoundDisplay()

  openEndRoundDisplay: (points, rounds, totalPoints) ->
    height = @$('#guess-word-bar').outerHeight() +
                          @$pickLettersBar.outerHeight()

    @$endRoundDisplay.css('height', height)
                     .fadeIn()

LW.Views.Timer = Backbone.View.extend
  start: ->
    @secs = 45
    @render()

    @timer = setInterval( =>
      @secs -= 1
      @render()
      @checkForTimeUp()
    , 1000)

  render: ->
    secsInMins = @toMins(@secs)
    @$el.html(secsInMins)

  toMins: (secs) ->
    currentMinutes = Math.floor(secs / 60);
    currentSeconds = secs % 60;
    if (currentSeconds <= 9) then currentSeconds = "0" + currentSeconds

    return currentMinutes + ":" + currentSeconds

  checkForTimeUp: ->
      if @secs <= 0
        clearInterval(@timer)
        LW.gameBoard.endRound()

  stop: ->
    clearInterval(@timer) if @timer

LW.Views.Score = Backbone.View.extend
  initialize: (options) ->
    @render()

    @listenTo @model, 'change', @render

  render: ->
    @$el.html( @model.get('pts') )

LW.Views.EndRound = Backbone.View.extend
  initialize: ->
    @listenTo @model, 'change', @render

  render: ->
    currentPts = @model.get('score').get('currentPts')
    avg = @model.get('score').get('pts') / @model.get('rounds')
    @$el
      .find('.end-round-score-display')
      .html(
        'You scored ' + currentPts + 
        ' points! Avg/round: ' + avg
      )
