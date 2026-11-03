# CallRefsAgree

`c.homes = []` makes `RefsAgree.homes` vacuous. For `refs`: binding a local whose cell is the next one, in a state whose cells and locals are below the next cell, makes the local's value the bound one and leaves the other locals' values. So a local of the callee is some binding's value (none from no locals), and the hypothesis gives `RefTo`.
