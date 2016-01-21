require 'constants'
require 'QApprox'
local util = require 'util'
local nn = require 'nn'
local nngraph = require 'nngraph'
local dpnn = require 'dpnn'

-- Implementation of a state-action value function approx using a neural network
local QNN, parent = torch.class('QNN', 'QApprox')

local function get_module(self)
    local x = nn.Identity()() -- use nngraph for practice
    local l1 = nn.Linear(self.n_features, 1)(x)
    --[[
    local l2 = nn.Sigmoid()(l1)
    local l3 = nn.Linear(self.n_features, self.n_features)(l2)
    local l4 = nn.Sigmoid()(l3)
    local l5 = nn.Linear(self.n_features, 1)(l4)
    --]]
    return nn.gModule({x}, {l1})
end

function QNN:__init(mdp, feature_extractor)
    parent.__init(self, mdp, feature_extractor)
    self.n_features = feature_extractor:get_sa_num_features()
    self.module = get_module(self)
end

function QNN:clear()
    self.module = get_module(self)
end

function QNN:get_value(s, a)
    local input = self.feature_extractor:get_sa_features(s, a)
    return self.module:forward(input)[1]
end

-- For now, we're ignoring eligibility. This means that the update rule to the
-- parameters W of the network is:
--
--      W <- W + step_size * td_error * dQ(s,a)/dW
--
-- We can force the network to update this way by recognizing that the "loss"
-- is literally just the output of the network. This makes it so that
--
--      dLoss/dW = dQ(s, a)/dW
--
-- So, the network will update correctly if we just tell it that the output is
-- the loss, i.e. set grad_out = 1.
--
-- For more detail where the update rule, see
-- https://webdocs.cs.ualberta.ca/~sutton/book/ebook/node89.html
--
-- For more detail on how nn works, see
-- https://github.com/torch/nn/blob/master/doc/module.md
--
-- TODO: include eligibility traces
function QNN:backward(s, a, learning_rate, momentum)
    -- forward to make sure input is set correctly
    local input = self.feature_extractor:get_sa_features(s, a)
    local output = self.module:forward(input)
    -- backward
    local grad_out = torch.ones(#output)
    self.module:zeroGradParameters()
    self.module:backward(input, grad_out)
    -- update
    self.module:updateGradParameters(momentum, 0, false) -- momentum (dpnn)
    -- ^ momentum MIGHT effectively implement eligibilty traces. It'd be
    -- interesting to look into this.
    self.module:updateParameters(-learning_rate) -- W = W - rate * dL/dW
end

QNN.__eq = parent.__eq -- force inheritance of this
