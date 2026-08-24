package com.moodpatterndiary.app.ui

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Button
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.moodpatterndiary.app.domain.GuidingQuestion
import com.moodpatterndiary.app.domain.GuidingQuestionAnswer
import com.moodpatterndiary.app.domain.QuestionTrigger

/**
 * Sequential guided-question entry flow (FR-004/FR-006, US2). Always shows the single mandatory
 * general prompt first, then 0-2 optional prompts chosen client-side as the user types
 * ([QuestionTrigger] -- research.md §1, zero network calls mid-entry). A "write freely instead"
 * exit is always visible per FR-005.
 */
@Composable
fun GuidedQuestionFlow(
    library: List<GuidingQuestion>,
    onBypassToFreeform: () -> Unit,
    onComplete: (List<GuidingQuestionAnswer>) -> Unit,
) {
    val mandatoryQuestions = remember(library) { library.filter { it.isMandatory } }
    var optionalQuestions by remember { mutableStateOf<List<GuidingQuestion>>(emptyList()) }
    var stepIndex by rememberSaveable { mutableIntStateOf(0) }
    val answers = remember { mutableStateMapOf<String, String>() }
    val mandatoryText = mandatoryQuestions.joinToString(" ") { answers[it.key].orEmpty() }

    LaunchedEffect(mandatoryText, library) {
        optionalQuestions = QuestionTrigger.matchingOptionalQuestions(mandatoryText, library)
    }

    val questions = mandatoryQuestions + optionalQuestions
    val totalSteps = questions.size.coerceAtLeast(1)

    Column(modifier = Modifier.fillMaxSize().padding(24.dp)) {
        LinearProgressIndicator(
            progress = { (stepIndex + 1) / totalSteps.toFloat() },
            modifier = Modifier.fillMaxWidth(),
        )
        Spacer(modifier = Modifier.height(24.dp))

        AnimatedContent(
            targetState = stepIndex,
            modifier = Modifier.weight(1f),
            transitionSpec = {
                (slideInHorizontally(tween(250)) { width -> width } + fadeIn(tween(250))) togetherWith
                    (slideOutHorizontally(tween(250)) { width -> -width } + fadeOut(tween(250)))
            },
            label = "guided-question-step",
        ) { step ->
            val question = questions.getOrNull(step)
            if (question != null) {
                QuestionStep(
                    prompt = question.promptText,
                    value = answers[question.key].orEmpty(),
                    onValueChange = { answers[question.key] = it },
                )
            } else {
                QuestionStep(
                    prompt = "What's been happening?",
                    value = answers["fallback"].orEmpty(),
                    onValueChange = { answers["fallback"] = it },
                )
            }
        }

        Spacer(modifier = Modifier.height(16.dp))

        TextButton(onClick = onBypassToFreeform) {
            Text("Write freely instead")
        }

        Spacer(modifier = Modifier.height(8.dp))

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            if (stepIndex > 0) {
                OutlinedButton(onClick = { stepIndex -= 1 }) { Text("Back") }
            } else {
                Spacer(modifier = Modifier.width(1.dp))
            }

            val isLastStep = stepIndex == totalSteps - 1
            val currentQuestion = questions.getOrNull(stepIndex)
            val canAdvance =
                currentQuestion == null ||
                    !currentQuestion.isMandatory ||
                    !answers[currentQuestion.key].isNullOrBlank()

            Button(
                onClick = {
                    if (isLastStep) {
                        val submittedAnswers =
                            buildList {
                                questions.forEach { question ->
                                    val answer = answers[question.key]
                                    if (!answer.isNullOrBlank()) {
                                        add(GuidingQuestionAnswer(question.key, answer.trim()))
                                    }
                                }
                            }
                        onComplete(submittedAnswers)
                    } else {
                        stepIndex += 1
                    }
                },
                enabled = canAdvance,
            ) {
                Text(if (isLastStep) "Save entry" else "Next")
            }
        }
    }
}

@Composable
private fun QuestionStep(
    prompt: String,
    value: String,
    onValueChange: (String) -> Unit,
) {
    Column(modifier = Modifier.fillMaxSize()) {
        Text(text = prompt, style = MaterialTheme.typography.headlineSmall)
        Spacer(modifier = Modifier.height(20.dp))
        OutlinedTextField(
            value = value,
            onValueChange = onValueChange,
            modifier = Modifier.fillMaxWidth(),
            placeholder = { Text("Type your answer…") },
            minLines = 4,
        )
    }
}
