from xmipy import XmiWrapper


class RibasimApi(XmiWrapper):
    def get_constant_int(self, name: str) -> int:
        match name:
            case "BMI_LENVARTYPE":
                return 51
            case "BMI_LENGRIDTYPE":
                return 17
            case "BMI_LENVARADDRESS":
                return 68
            case "BMI_LENCOMPONENTNAME":
                return 256
            case "BMI_LENVERSION":
                return 256
            case "BMI_LENERRMESSAGE":
                return 1025
        raise ValueError(f"{name} does not map to an integer exposed by Ribasim")

    def update_subgrid_level(self) -> None:
        self.lib.update_subgrid_level()

    def execute(self, config_file: str) -> None:
        self._execute_function(self.lib.execute, config_file.encode())
