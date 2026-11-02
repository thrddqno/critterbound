--!strict

local Harness = require("./TestHarness")

require("./Unit/DomainValidator.spec")(Harness)
require("./Unit/BattlePhase.spec")(Harness)
require("./Unit/Initiative.spec")(Harness)

Harness.run()
