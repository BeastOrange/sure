# 当前项目优化巡检报告

生成时间：2026-06-11 08:20  
巡检范围：Rails 应用代码、前端脚本、国际化、静态检查、安全扫描、文档与配置一致性。

## 结论

项目整体基础不错：Ruby lint、JS lint、Zeitwerk autoload 检查、设计 token 生成检查都通过，没有发现直接阻断本地开发的结构性问题。

当前最值得优先处理的是中文化完整度、前端/ERB 格式门禁、Rails 版本生命周期，以及少量配置和生产风险 TODO。下面按优先级列出。

## P0：优先处理

### 补齐 zh-CN 缺失翻译

`zh-CN` 已被设为默认语言，但仍有 908 个缺失翻译键。由于 `config.i18n.fallbacks = true` 仍开启，很多缺失项不会报错，而是回退到英文；这会造成页面中英文混排，也会让真实缺失在测试中不容易暴露。

证据：

```sh
bundle exec i18n-tasks missing -f keys -l zh-CN | rg '^zh-CN\.' | wc -l
# 908
```

缺口最大的命名空间：

```text
214 goals
162 settings
134 imports
75 akahu_items
51 provider_sync_summary
32 activerecord
27 brex_items
17 transfers
16 transactions
14 categories
```

建议：

1. 先补用户最常访问页面：`settings`、`imports`、`transactions`、`categories`。
2. 再补新增功能或新页面：`goals`、`goal_pledges`。
3. 保留 fallback 作为过渡，但新增一条 CI 检查，至少限制 `zh-CN` 缺失数量不能继续增加。
4. 给报告页、设置页、导入页增加少量 smoke/integration test，断言页面没有 `translation missing`。

### 修复格式检查门禁不一致

`npm run lint` 通过，但 `npm run format:check` 失败，说明当前 JS 代码并不满足格式化规则。ERB lint 也有 20 个错误。若 CI 未覆盖这些命令，后续改动会持续带入格式噪音。

证据：

```sh
npm run lint
# Checked 101 files. No fixes applied.

npm run format:check
# Found 61 errors.

bundle exec erb_lint --lint-all
# 20 error(s) were found in ERB files
```

典型问题：

```text
app/javascript/controllers/admin_invitation_delete_controller.js
app/javascript/controllers/account_type_selector_controller.js
app/javascript/controllers/attachment_upload_controller.js
app/views/impersonation_sessions/_super_admin_bar.html.erb
app/views/layouts/print.html.erb
app/views/transfers/_form.html.erb
```

建议：

1. 单独开一个格式化 PR，只做 `npm run format` 和 ERB lint 可自动修复项。
2. 格式化 PR 不混入业务逻辑，降低 review 成本。
3. 在 CI 中明确运行 `npm run format:check` 和 `bundle exec erb_lint --lint-all`。

## P1：近期处理

### 规划 Rails 7.2 升级窗口

Brakeman 只报了一个安全相关警告：当前 Rails 7.2.3.1 的支持将在 2026-08-09 结束。今天是 2026-06-11，剩余窗口较短，建议提前规划到受维护版本。

证据：

```sh
bin/brakeman -q
# Security Warnings: 1
# Support for Rails 7.2.3.1 ends on 2026-08-09
```

建议：

1. 先升级到当前 Rails 7.2 最新 patch 版本，降低安全风险。
2. 再评估 Rails 8 升级成本，重点关注 Active Storage、Propshaft、autoload、encrypted credentials、test helpers。
3. 升级前跑完整测试和 Brakeman，升级后对认证、导入、同步、报表、API 做回归。

### 拆分超大控制器和服务对象

项目里有多个超过 1,000 行的文件。它们不是立即错误，但会增加回归风险、测试成本和并行开发冲突概率。

证据：

```text
1451 app/models/demo/generator.rb
1342 app/models/simplefin_item/importer.rb
1261 app/models/family/data_importer.rb
1250 app/controllers/sophtron_items_controller.rb
1147 app/controllers/reports_controller.rb
1024 app/models/account/provider_import_adapter.rb
713  config/routes.rb
```

建议：

1. 先拆 `ReportsController`：把 period 解析、数据聚合、图表 payload、导出逻辑分别移到 query/service 对象。
2. 再拆 provider importer：每个 provider 保留 orchestration，解析、映射、持久化、错误归一化分层处理。
3. `config/routes.rb` 可按 admin、api、providers、settings、accounts 等 namespace 拆成 route concern 或 draw 文件。

### 清理生产风险 TODO

大部分 TODO 在 generator template 中，风险较低；但有几处在运行时代码中，建议排期处理。

需要关注：

```text
app/models/enable_banking_item.rb:51
# last_psu_ip 数据保留策略，涉及 GDPR/CCPA

app/models/enable_banking_account/processor.rb:86
# 同步时缺少 explicit window_start_date，可能导致每次同步都做全历史重算

app/jobs/indexa_capital_connection_cleanup_job.rb:43
# 删除连接 API 尚未实现

app/models/mercury_item.rb
# 多处 provider 导入/处理逻辑仍是 TODO
```

建议：

1. 先处理 `last_psu_ip` 保留策略，给出明确清理任务和测试。
2. 给 Enable Banking 同步窗口加参数化测试，避免全量重算成为性能问题。
3. 对未完成 provider 增加 feature flag 或 UI 标记，避免用户误以为已完整可用。

## P2：中期优化

### 修正 package.json license

仓库根目录 `LICENSE` 是 AGPLv3，README 也说明项目使用 AGPLv3；但 `package.json` 写的是 `ISC`。这会让依赖扫描、许可证审计、发布元数据产生冲突。

证据：

```json
"license": "ISC"
```

建议：

将 `package.json` 的 license 改为与仓库一致的 `AGPL-3.0-only` 或 `AGPL-3.0-or-later`。具体选哪个应和项目法律/上游授权口径保持一致。

### 明确前端格式化脚本命名

`package.json` 中同时有：

```json
"style:check": "biome check",
"lint": "biome lint",
"format:check": "biome format"
```

`format:check` 当前运行的是 `biome format`，实际是检查并输出差异，不会写入文件。命名可以接受，但建议在 README 或贡献文档中明确：

```sh
npm run lint
npm run format:check
npm run format
```

这样可以避免开发者只跑 `npm run lint` 就以为前端质量门禁全部通过。

### 完善中文默认语言后的验收清单

当前 locale 优先级是：

```ruby
locale_from_param || locale_from_user || locale_from_family || I18n.default_locale || locale_from_accept_language
```

这符合“默认中文”的目标，但也意味着浏览器 `Accept-Language` 基本只在前面都缺失时才生效。建议把这一点写入开发文档，避免后续维护者误以为浏览器语言优先。

建议验收清单：

1. 新访客默认看到中文。
2. 登录用户优先使用个人 locale。
3. 家庭 locale 覆盖默认中文。
4. URL `locale` 参数可临时覆盖。
5. 页面不能出现 `translation missing`。

## 已验证为健康的部分

这些检查结果是绿色的：

```sh
bin/rubocop
# 1905 files inspected, no offenses detected

npm run lint
# Checked 101 files. No fixes applied.

npm run tokens:check
# generated design token CSS 与仓库一致

bin/rails zeitwerk:check
# Otherwise, all is good!
```

`zeitwerk:check` 只提示 preview 目录未纳入 eager load 检查。若 preview 组件不是生产路径，这不是高优先级问题；若依赖 Lookbook/component previews 做设计系统回归，可以考虑把相关 preview 路径纳入单独检查。

## 建议执行顺序

1. 修 `zh-CN` 缺失翻译，并加“不新增缺失键”的 CI 保护。
2. 做一个纯格式化 PR，修复 Biome format 和 ERB lint。
3. 创建 Rails patch 升级任务，升级前后跑完整回归。
4. 拆分 `ReportsController` 和 provider importer 中最常改的路径。
5. 处理数据保留与同步窗口 TODO。
6. 修正 `package.json` license。

## 本次巡检命令

```sh
git status --short --branch
bin/rubocop
bin/brakeman -q
npm run lint
npm run format:check
npm run tokens:check
bundle exec erb_lint --lint-all
bundle exec i18n-tasks missing -l zh-CN
bundle exec i18n-tasks unused -l zh-CN
bin/rails zeitwerk:check
```

