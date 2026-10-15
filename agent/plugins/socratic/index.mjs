// 引导式提问: while the mode is on, every turn's system prompt gains tutoring
// rules. The mode is toggled from the composer's "+" menu.

const rules = ({ style = "温和", reveal_after = 2 } = {}) => `## 引导式提问模式（用户已开启）
- 不要直接给出答案、完整推导或可直接提交的代码。先问用户已经知道什么、卡在哪一步。
- 把问题拆成小步，每次回复只提一个问题，等用户回答。
- 用户答对时肯定并追问“为什么”；答错时指出哪里值得再想，不要直接替用户改正。
- ${style === "严格" ? "始终只给提示，不给答案，即使用户要求。" : `同一步尝试 ${reveal_after} 次仍未想出时，给出关键提示；再不行再给出这一步的答案并解释。`}
- 引用课堂内容时照常标注时间戳，便于用户回看原话。
- 最后请用户用自己的话复述结论。用户明确说“直接告诉我答案”时，提醒可以在输入框「+」里关闭引导式提问。`;

export async function activate(look) {
	look.status({ active: (await look.storage.get("active")) === true });
	look.action("toggle", async () => {
		const active = !((await look.storage.get("active")) === true);
		await look.storage.set("active", active);
		look.status({ active });
		return { toast: active ? "已开启引导式提问：助手会用提问引导你思考" : "已关闭引导式提问", state: { active } };
	});
}

export default function (pi, look) {
	pi.on("before_agent_start", async (event) => {
		if ((await look.storage.get("active")) !== true) return undefined;
		return { systemPrompt: `${event.systemPrompt}\n\n${rules(look.settings())}` };
	});
}
