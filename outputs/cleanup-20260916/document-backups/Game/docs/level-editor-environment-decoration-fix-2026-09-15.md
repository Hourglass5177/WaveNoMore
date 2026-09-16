# 初始环境切换后装饰残留修复

根因：随机横向拼接的祭品等装饰保存在独立 HorizontalRepeatView 中，普通配置对象数组对应位置是空占位。原先换景只遍历该数组隐藏素材，漏掉随机装饰及其后续生成的副本。

现在统一隐藏基础背景的显示宿主，覆盖普通素材和随机装饰。角色、音符与演出对象注册不受影响。恢复沿用原环境、清除换景安排时恢复基础宿主；不再改写素材自身的显隐，避免原本隐藏的素材被强制显示。

验证使用教程关真实背景（含随机装饰）：修复前三项失败；修复后替换、移动镜头、继续采样、恢复和清除安排均通过，角色注册保持不变。GPU 截图显示所选蓝色环境，没有旧祭品残留。初始环境实际按钮选择、撤销、重做以及运行时环境回归通过，最终日志无引擎错误。

证据位于 Levels/output/environment-decoration-before.log、environment-decoration-after.log、environment-decoration-runtime.log、environment-decoration-entry.log 和 environment-decoration/replaced.png。本轮未构建 EXE。
