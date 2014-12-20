angular.module('omega').controller 'MasterCtrl', ($scope, $rootScope, $window,
  $q, $modal, $state, profileColors, profileIcons, omegaTarget,
  $timeout, $location, $filter, getAttachedName, isProfileNameReserved,
  isProfileNameHidden, dispNameFilter) ->

  tr = $filter('tr')

  $rootScope.options = null

  omegaTarget.addOptionsChangeCallback (newOptions) ->
    $rootScope.options = angular.copy(newOptions)
    $rootScope.optionsOld = angular.copy(newOptions)
    $timeout ->
      $rootScope.optionsDirty = false
  
  $rootScope.revertOptions = ->
    $window.location.reload()

  $rootScope.exportScript = (name) ->
    getProfileName =
      if name
        $q.when(name)
      else
        omegaTarget.state('currentProfileName')
          
    getProfileName.then (profileName) ->
      return unless profileName
      profile = $rootScope.profileByName(profileName)
      return if profile.profileType in ['DirectProfile', 'SystemProfile']
      missingProfile = null
      profileNotFound = (name) ->
        missingProfile = name
        return 'dumb'
      ast = OmegaPac.PacGenerator.script($rootScope.options, profileName,
        profileNotFound: profileNotFound)
      pac = ast.print_to_string(beautify: true, comments: true)
      pac = OmegaPac.PacGenerator.ascii(pac)
      blob = new Blob [pac], {type: "text/plain;charset=utf-8"}
      fileName = profileName.replace(/\W+/g, '_')
      saveAs(blob, "OmegaProfile_#{fileName}.pac")
      if missingProfile
        $timeout ->
          $rootScope.showAlert(
            type: 'error'
            message: tr('options_profileNotFound', [missingProfile])
          )

  diff = jsondiffpatch.create(
    objectHash: (obj) -> JSON.stringify(obj)
    textDiff: minLength: 1 / 0
  )

  $rootScope.showAlert = (alert) -> $timeout ->
    $scope.alert = alert
    $scope.alertShown = true
    $scope.alertShownAt = Date.now()
    $timeout $rootScope.hideAlert, 3000
    return

  $rootScope.hideAlert = -> $timeout ->
    if Date.now() - $scope.alertShownAt >= 1000
      $scope.alertShown = false

  checkFormValid = ->
    fields = angular.element('.ng-invalid')
    if fields.length > 0
      fields[0].focus()
      $rootScope.showAlert(
        type: 'error'
        i18n: 'options_formInvalid'
      )
      return false
    return true

  $rootScope.applyOptions = ->
    return unless checkFormValid()
    plainOptions = angular.fromJson(angular.toJson($rootScope.options))
    patch = diff.diff($rootScope.optionsOld, plainOptions)
    omegaTarget.optionsPatch(patch).then ->
      $rootScope.showAlert(
        type: 'success'
        i18n: 'options_saveSuccess'
      )

  $rootScope.resetOptions = (options) ->
    omegaTarget.resetOptions(options).then(->
      $rootScope.showAlert(
        type: 'success'
        i18n: 'options_resetSuccess'
      )
    ).catch (err) ->
      $rootScope.showAlert(
        type: 'error'
        message: err
      )
      $q.reject err

  $rootScope.profileByName = (name) ->
    OmegaPac.Profiles.byName(name, $rootScope.options)

  $rootScope.applyOptionsConfirm = ->
    return $q.reject 'form_invalid' unless checkFormValid()
    return $q.when(true) unless $rootScope.optionsDirty
    $modal.open(templateUrl: 'partials/apply_options_confirm.html').result
      .then -> $rootScope.applyOptions()

  $rootScope.newProfile = ->
    scope = $rootScope.$new('isolate')
    scope.options = $rootScope.options
    scope.isProfileNameReserved = isProfileNameReserved
    scope.isProfileNameHidden = isProfileNameHidden
    scope.profileByName = $rootScope.profileByName
    scope.validateProfileName =
      conflict: '!$value || !profileByName($value)'
      reserved: '!$value || !isProfileNameReserved($value)'
    scope.profileIcons = profileIcons
    scope.dispNameFilter = dispNameFilter
    scope.options = $scope.options
    $modal.open(
      templateUrl: 'partials/new_profile.html'
      scope: scope
    ).result.then (profile) ->
      profile = OmegaPac.Profiles.create(profile)
      choice = Math.floor(Math.random() * profileColors.length)
      profile.color ?= profileColors[choice]
      OmegaPac.Profiles.updateRevision(profile)
      $rootScope.options[OmegaPac.Profiles.nameAsKey(profile)] = profile
      $state.go('profile', {name: profile.name})

  $rootScope.replaceProfile = (fromName, toName) ->
    $rootScope.applyOptionsConfirm().then ->
      scope = $rootScope.$new('isolate')
      scope.options = $rootScope.options
      scope.fromName = fromName
      scope.toName = toName
      scope.profileByName = $rootScope.profileByName
      scope.dispNameFilter = dispNameFilter
      scope.options = $scope.options
      scope.profileSelect = (model) ->
        """
        <div omega-profile-select="options | profiles:profile"
          ng-model="#{model}" options="options"
          disp-name="dispNameFilter" style="display: inline-block;">
        </div>
        """
      $modal.open(
        templateUrl: 'partials/replace_profile.html'
        scope: scope
      ).result.then ({fromName, toName}) ->
        omegaTarget.replaceRef(fromName, toName).then(->
          $rootScope.showAlert(
            type: 'success'
            i18n: 'options_replaceProfileSuccess'
          )
        ).catch (err) ->
          $rootScope.showAlert(
            type: 'error'
            message: err
          )


  $rootScope.renameProfile = (fromName) ->
    $rootScope.applyOptionsConfirm().then ->
      profile = $rootScope.profileByName(fromName)
      scope = $rootScope.$new('isolate')
      scope.options = $rootScope.options
      scope.fromName = fromName
      scope.isProfileNameReserved = isProfileNameReserved
      scope.isProfileNameHidden = isProfileNameHidden
      scope.profileByName = $rootScope.profileByName
      scope.validateProfileName =
        conflict: '!$value || $value == fromName || !profileByName($value)'
        reserved: '!$value || !isProfileNameReserved($value)'
      scope.dispNameFilter = $scope.dispNameFilter
      scope.options = $scope.options
      $modal.open(
        templateUrl: 'partials/rename_profile.html'
        scope: scope
      ).result.then (toName) ->
        if toName != fromName
          rename = omegaTarget.renameProfile(fromName, toName)
          attachedName = getAttachedName(fromName)
          if $rootScope.profileByName(attachedName)
            toAttachedName = getAttachedName(toName)
            defaultProfileName = undefined
            if $rootScope.profileByName(toAttachedName)
              defaultProfileName = profile.defaultProfileName
              rename = rename.then ->
                toAttachedKey = OmegaPac.Profiles.nameAsKey(toAttachedName)
                profile = $rootScope.profileByName(toName)
                profile.defaultProfileName = 'direct'
                OmegaPac.Profiles.updateRevision(profile)
                delete $rootScope.options[toAttachedKey]
                $rootScope.applyOptions()
            rename = rename.then ->
              omegaTarget.renameProfile(attachedName, toAttachedName)
            if defaultProfileName
              rename = rename.then ->
                profile = $rootScope.profileByName(toName)
                profile.defaultProfileName = defaultProfileName
                $rootScope.applyOptions()
          rename.then(->
            $state.go('profile', {name: toName})
          ).catch (err) ->
            $rootScope.showAlert(
              type: 'error'
              message: err
            )

  $scope.updatingProfile = {}

  $rootScope.updateProfile = (name) ->
    $rootScope.applyOptionsConfirm().then(->
      $scope.updatingProfile[name] = true
      omegaTarget.updateProfile(name).then((results) ->
        success = 0
        error = 0
        for own profileName, result of results
          if result instanceof Error
            error++
          else
            success++
        if error == 0
          $rootScope.showAlert(
            type: 'success'
            i18n: 'options_profileDownloadSuccess'
          )
        else
          $q.reject(results)
      ).catch((err) ->
        $rootScope.showAlert(
          type: 'error'
          i18n: 'options_profileDownloadError'
        )
      ).finally ->
        $scope.updatingProfile[name] = false
    )

  onOptionChange = (options, oldOptions) ->
    return if options == oldOptions or not oldOptions?
    $rootScope.optionsDirty = true
  $rootScope.$watch 'options', onOptionChange, true

  $rootScope.$on '$stateChangeStart', (event, _, __, fromState) ->
    if not checkFormValid()
      event.preventDefault()

  $rootScope.$on '$stateChangeSuccess', ->
    omegaTarget.lastUrl($location.url())

  $window.onbeforeunload = ->
    if $rootScope.optionsDirty
      return tr('options_optionsNotSaved')
    else
      null

  document.addEventListener 'click', (->
    $rootScope.hideAlert()
  ), false

  $scope.profileIcons = profileIcons
  $scope.dispNameFilter = dispNameFilter

  for own type of OmegaPac.Profiles.formatByType
    $scope.profileIcons[type] = $scope.profileIcons['RuleListProfile']

  $scope.alertIcons =
    'success': 'glyphicon-ok',
    'warning': 'glyphicon-warning-sign',
    'error': 'glyphicon-remove',
    'danger': 'glyphicon-danger',

  $scope.alertClassForType = (type) ->
    return '' if not type
    if type == 'error'
      type = 'danger'
    return 'alert-' + type

  $scope.downloadIntervals = [15, 60, 180, 360, 720, 1440, -1]
  $scope.downloadIntervalI18n = (interval) ->
    "options_downloadInterval_" + (if interval < 0 then "never" else interval)

  omegaTarget.refresh()

  omegaTarget.state('firstRun').then (firstRun) ->
    return unless firstRun
    scope = $rootScope.$new('isolate')
    scope.upgrade = (firstRun == 'upgrade')
    $modal.open(
      templateUrl: 'partials/options_welcome.html'
      keyboard: false
      scope: scope
      backdrop: 'static'
      backdropClass: 'opacity-half'
    ).result.then (r) ->
      switch r
        when 'later'
          return
        when 'show'
          $script 'js/options_guide.js'
        when 'skip'
          break
      omegaTarget.state('firstRun', '')
