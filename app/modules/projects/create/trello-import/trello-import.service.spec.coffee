describe "tgTrelloImportService", ->
    $provide = null
    $rootScope = null
    $q = null
    service = null
    mocks = {}

    _mockResources = ->
        mocks.resources = {
            trelloImporter: {
                listProjects: sinon.stub(),
                listUsers: sinon.stub(),
                importProject: sinon.stub(),
                getAuthUrl: sinon.stub(),
                authorize: sinon.stub()
            }
        }

        $provide.value("tgResources", mocks.resources)

    _mocks = ->
        module (_$provide_) ->
            $provide = _$provide_

            _mockResources()

            return null

    _inject = ->
        inject (_tgTrelloImportService_, _$rootScope_, _$q_) ->
            service = _tgTrelloImportService_
            $rootScope = _$rootScope_
            $q = _$q_

    _setup = ->
        _mocks()
        _inject()

    beforeEach ->
        module "taigaProjects"

        _setup()

    it "fetch projects", (done) ->
        service.setToken(123)
        mocks.resources.trelloImporter.listProjects.withArgs(123).promise().resolve('projects')

        service.fetchProjects().then () ->
            service.projects = "projects"
            done()

    it "fetch user", (done) ->
        service.setToken(123)
        projectId = 3
        mocks.resources.trelloImporter.listUsers.withArgs(123, projectId).promise().resolve('users')

        service.fetchUsers(projectId).then () ->
            service.projectUsers = 'users'
            done()

    it "import project", () ->
        service.setToken(123)
        projectId = 2

        service.importProject(projectId, true, true ,true)

        expect(mocks.resources.trelloImporter.importProject).to.have.been.calledWith(123, projectId, true, true, true)

    it "get auth url", (done) ->
        service.setToken(123)
        projectId = 3

        response = {
            data: {
                url: "url123"
            }
        }

        getAuthUrlDeferred = $q.defer()
        mocks.resources.trelloImporter.getAuthUrl.returns(getAuthUrlDeferred.promise)
        getAuthUrlDeferred.resolve(response)

        service.getAuthUrl().then (url) ->
            expect(url).to.be.equal("url123")
            done()

        $rootScope.$apply()

    it "authorize", (done) ->
        service.setToken(123)
        projectId = 3
        verifyCode = 12345

        response = {
            data: {
                token: "token123"
            }
        }

        authorizeDeferred = $q.defer()
        mocks.resources.trelloImporter.authorize.withArgs(verifyCode).returns(authorizeDeferred.promise)
        authorizeDeferred.resolve(response)

        service.authorize(verifyCode).then (token) ->
            expect(token).to.be.equal("token123")
            done()

        $rootScope.$apply()
