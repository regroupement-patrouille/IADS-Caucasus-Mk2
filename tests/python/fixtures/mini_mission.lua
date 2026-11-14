mission =
{
  coalition = {
    blue = {
      name = "blue",
      country = {
        [1] = {
          id = 2,
          name = "USA",
          vehicle = {
            group = {
              [1] = {
                groupId = 1,
                name = "SA-2 - Poti-unit-1",
                units = {
                  [1] = {
                    type = "1L13 EWR",
                    name = "Blue radar",
                    x = 10.5,
                    y = -20,
                  },
                },
              },
            },
          },
        },
      },
    },
    red = {
      name = "red",
      country = {
        [1] = {
          id = 0,
          name = "Russia",
          vehicle = {
            group = {
              [1] = {
                groupId = 2,
                name = "SA-2 - Poti",
                lateActivation = false,
                route = {
                  points = {
                    [1] = {
                      name = "SA-2 - Poti",
                      x = 1000,
                      y = 2000,
                      ["01_prfx_arm_delay"] = 4,
                    },
                  },
                },
                units = {
                  [1] = {
                    type = "SNR_75V",
                    name = "SA-2 - Poti-unit-1",
                    x = 1000,
                    y = 2000,
                  },
                  [2] = {
                    type = "S_75M_Volhov",
                    name = "SA-2 - Poti-unit-2",
                    x = 1010.25,
                    y = 2010,
                  },
                },
              },
            },
          },
          static = {
            group = {
              [1] = {
                name = "CommandCenterRed",
                units = {
                  [1] = {
                    type = ".Command Center",
                    name = "CommandCenterRed",
                    x = 5000,
                    y = 6000,
                  },
                },
              },
            },
          },
          plane = {
            group = {
              [1] = {
                name = "Awacs #3",
                units = {
                  [1] = {
                    type = "A-50",
                    name = "Awacs #3",
                    x = 7000,
                    y = 8000,
                    speed = 3e-05,
                  },
                },
              },
            },
          },
        },
      },
    },
  },
  trig = {
    actions = {
      [1] = "a_do_script(\"x = [[a \\\"b\\\"]] name = \\\"SA-2 - Poti\\\"\\\
y = 1\");",
    },
  },
  note = 'single quoted name = "SA-2 - Poti"',
}
