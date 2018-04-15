--[[
Autor:João Victor Oliveira Couto

Componente Curricular: Concorrência e Conectividade

Concluido em: 14/04/2018

Declaro que este código foi elaborado por mim de forma individual e não contém nenhum
trecho de código de outro colega ou de outro autor, tais como provindos de livros e
apostilas, e páginas ou documentos eletrônicos da Internet. Qualquer trecho de código
de outra autoria que não a minha está destacado com uma citação para o autor e a fonte
do código, e estou ciente que estes trechos não serão considerados para fins de avaliação.
--]]
local Server_TCP = {}
function Server_TCP:new(serverConn, databaseConn)
    local self = {
        clientConnection;
        databaseConnection;
        clientId;
        thread;
        constructor = function(this, serverConn, databaseConn)
            this.clientConnection = serverConn
            this.databaseConnection = databaseConn
            this.clientId = nil
            this.thread = nil
        end
    }
    self.constructor(self, serverConn, databaseConn)
    local function authenticateClient(message)
        if(message) then
            local beginig, ending = message:find("%[sensorID%]<")
            local sensorID = message:sub(ending):match("[a-zA-Z0-9,:]+")
            cursor = self.databaseConnection:execute(string.format("SELECT Client.client_id, Client.client_email from Client WHERE ip_client = '%s'", sensorID))
            local client_id, client_email = cursor:fetch()
            if(not client_id or not ending) then
                self.clientId = nil
                return false
            end
            self.clientId = client_id
            beginig, ending = message:find("%[clientMail%]<")
            client_email = message:sub(ending + 1, #message - 2)
            self.databaseConnection:execute(string.format("UPDATE Client SET client_email = '%s' WHERE ip_client = '%s'", client_email, sensorID))
            return true
        end
        return false
    end
    local function establishGoal(message)
        local goalString = message:gsub("%[goal%]:=", "")
        self.databaseConnection:execute(string.format("UPDATE Client SET expend_goal = %d WHERE client_id = %d", tonumber(goalString), self.clientId))
        self.databaseConnection:commit()
    end
    local function totalConsume()
        local consultCommand = [[
        SELECT SUM(Water_Consume.water_expended)
        FROM Client INNER JOIN Client_Expend ON Client.client_id = Client_Expend.fk_client_id INNER JOIN 
        Water_Consume ON Water_Consume.fk_water_expend_id = Client_Expend.water_expend_id WHERE Client.client_id = '%d'
        ]]
        return self.databaseConnection:execute(string.format(consultCommand, self.clientId)):fetch()
    end
    local function requireWater()
        local waterTable = {}
        local consultCommand = [[
        SELECT Water_Consume.water_expended, Water_Consume.last_syncronization, Client_Expend.expend_date
        FROM Client INNER JOIN Client_Expend ON Client.client_id = Client_Expend.fk_client_id INNER JOIN 
        Water_Consume ON Water_Consume.fk_water_expend_id = Client_Expend.water_expend_id WHERE Client.client_id = '%d'
        ]]
        local cursor = self.databaseConnection:execute(string.format(consultCommand, self.clientId))
        cursor:fetch(waterTable, "n")
        self.clientConnection:send(string.format("[waterConsume]<%d>)([dateTime]<%s %s>", tonumber(waterTable[1]), waterTable[3], waterTable[2]))
    end
    local function detectFunction(message)
        if(message) then
            local callFunction = message:match("%[.+%]"):gsub("%[", ""):gsub("%]", "")
            coroutine.yield()
            if(callFunction == "goal") then
                establishGoal(message)
            elseif(callFunction == "requireWater") then
                local totalExpend = totalConsume()
                print(totalExpend)
                self.clientConnection:send(string.format("[totalWater]:=%f\n", totalExpend))
                requireWater()
            end
        end
    end
    local function mainExecution()
        local message = self.clientConnection:receive()
        detectFunction(message)
        --self.clientConnection:close()
        self.thread[self.clientId] = nil
    end
    local function tableThread()
        self.thread[self.clientId] = coroutine.create(mainExecution)
    end
    local function start()
        self.clientConnection:settimeout(0.01)
        if(authenticateClient(self.clientConnection:receive())) then
            local ok, err = self.clientConnection:send("$YESAUT\n")
            --print(ok, err)
            tableThread()
        else
            local ok, err = self.clientConnection:send("$NOTAUT\n")
            --print(ok, err)
        end
    end
    local function setThreadTable(thread)
        self.thread = thread
    end
    return {
        start = start;
        setThreadTable = setThreadTable;
    }
end
return Server_TCP
